// NFC Card Manager Core Logic with Deep Inspector, Hex Viewer & AES-256

const nfcSupportBadge = document.getElementById('nfcSupportBadge');
const encryptionStatusBadge = document.getElementById('encryptionStatusBadge');
const writableStatus = document.getElementById('writableStatus');
const btnScan = document.getElementById('btnScan');
const btnWrite = document.getElementById('btnWrite');
const btnWipeTag = document.getElementById('btnWipeTag');
const btnProbeWritable = document.getElementById('btnProbeWritable');
const btnClear = document.getElementById('btnClear');
const btnQuickSample = document.getElementById('btnQuickSample');
const btnClearHistory = document.getElementById('btnClearHistory');
const btnDecryptManual = document.getElementById('btnDecryptManual');
const btnToggleKey = document.getElementById('btnToggleKey');

const secretKeyInput = document.getElementById('secretKey');
const enableEncryption = document.getElementById('enableEncryption');

const statusBox = document.getElementById('statusBox');
const statusMsg = document.getElementById('statusMsg');
const spinner = document.getElementById('spinner');

const cardSerial = document.getElementById('cardSerial');
const recordType = document.getElementById('recordType');
const cardContent = document.getElementById('cardContent');
const hexCardContent = document.getElementById('hexCardContent');
const rawCardContent = document.getElementById('rawCardContent');
const historyList = document.getElementById('historyList');

const tabPlain = document.getElementById('tabPlain');
const tabHex = document.getElementById('tabHex');
const tabRaw = document.getElementById('tabRaw');
const plainView = document.getElementById('plainView');
const hexView = document.getElementById('hexView');
const rawView = document.getElementById('rawView');

let ndefReader = null;
let currentSerial = null;
let lastRawData = '';
let lastRawBytes = new Uint8Array(0);
const STORAGE_KEY = 'nfc_cards_encrypted_history';
const MAGIC_HEADER = 'ENC:v1:';

// ------------------------------------------------------------------
// 1. Web Cryptography Functions (AES-GCM 256-bit with PBKDF2)
// ------------------------------------------------------------------

function bufToHex(buffer) {
  return [...new Uint8Array(buffer)]
    .map(x => x.toString(16).padStart(2, '0'))
    .join('');
}

function hexToBuf(hexString) {
  const bytes = new Uint8Array(hexString.length / 2);
  for (let i = 0; i < bytes.length; i++) {
    bytes[i] = parseInt(hexString.substr(i * 2, 2), 16);
  }
  return bytes;
}

function bufToBase64(buffer) {
  let binary = '';
  const bytes = new Uint8Array(buffer);
  const len = bytes.byteLength;
  for (let i = 0; i < len; i++) {
    binary += String.fromCharCode(bytes[i]);
  }
  return window.btoa(binary);
}

function base64ToBuf(base64) {
  const binary_string = window.atob(base64);
  const len = binary_string.length;
  const bytes = new Uint8Array(len);
  for (let i = 0; i < len; i++) {
    bytes[i] = binary_string.charCodeAt(i);
  }
  return bytes;
}

async function deriveKey(passphrase, salt) {
  const enc = new TextEncoder();
  const keyMaterial = await window.crypto.subtle.importKey(
    'raw',
    enc.encode(passphrase),
    { name: 'PBKDF2' },
    false,
    ['deriveKey']
  );

  return await window.crypto.subtle.deriveKey(
    {
      name: 'PBKDF2',
      salt: salt,
      iterations: 100000,
      hash: 'SHA-256'
    },
    keyMaterial,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

async function encryptPayload(plaintext, passphrase) {
  const enc = new TextEncoder();
  const salt = window.crypto.getRandomValues(new Uint8Array(16));
  const iv = window.crypto.getRandomValues(new Uint8Array(12));
  const key = await deriveKey(passphrase, salt);

  const encryptedBuf = await window.crypto.subtle.encrypt(
    { name: 'AES-GCM', iv: iv },
    key,
    enc.encode(plaintext)
  );

  const saltHex = bufToHex(salt);
  const ivHex = bufToHex(iv);
  const cipherB64 = bufToBase64(encryptedBuf);

  return `${MAGIC_HEADER}${saltHex}:${ivHex}:${cipherB64}`;
}

async function decryptPayload(payload, passphrase) {
  if (!payload || !payload.startsWith(MAGIC_HEADER)) {
    return { isEncrypted: false, plaintext: payload, error: null };
  }

  try {
    const parts = payload.substring(MAGIC_HEADER.length).split(':');
    if (parts.length !== 3) {
      throw new Error('تنسيق التشفير غير صالح');
    }

    const salt = hexToBuf(parts[0]);
    const iv = hexToBuf(parts[1]);
    const cipherBuf = base64ToBuf(parts[2]);

    const key = await deriveKey(passphrase, salt);
    const decryptedBuf = await window.crypto.subtle.decrypt(
      { name: 'AES-GCM', iv: iv },
      key,
      cipherBuf
    );

    const dec = new TextDecoder();
    return {
      isEncrypted: true,
      plaintext: dec.decode(decryptedBuf),
      error: null
    };
  } catch (err) {
    return {
      isEncrypted: true,
      plaintext: null,
      error: 'المفتاح السري غير صحيح أو تعذر فك التشفير'
    };
  }
}

// ------------------------------------------------------------------
// 2. Hex Dump Generator for Deep Tag Inspection
// ------------------------------------------------------------------

function generateHexDump(bytes) {
  if (!bytes || bytes.length === 0) return 'لا توجد بيانات ثنائية متاحة.';
  let output = '';
  const chunkSize = 16;

  for (let i = 0; i < bytes.length; i += chunkSize) {
    const chunk = bytes.slice(i, i + chunkSize);
    // Offset (e.g. 0000:)
    const offset = i.toString(16).padStart(4, '0').toUpperCase();

    // Hex representation
    let hexPart = '';
    let asciiPart = '';

    for (let j = 0; j < chunkSize; j++) {
      if (j < chunk.length) {
        const byte = chunk[j];
        hexPart += byte.toString(16).padStart(2, '0').toUpperCase() + ' ';
        // Printable ASCII check
        asciiPart += (byte >= 32 && byte <= 126) ? String.fromCharCode(byte) : '.';
      } else {
        hexPart += '   ';
      }
      if (j === 7) hexPart += ' '; // middle divider
    }

    output += `${offset}:  ${hexPart} |${asciiPart}|\n`;
  }

  return output;
}

// ------------------------------------------------------------------
// 3. Status Box & NFC Support
// ------------------------------------------------------------------

function checkNFCSupport() {
  if ('NDEFReader' in window) {
    nfcSupportBadge.textContent = 'Web NFC مدعومة ومتاحة ✅';
    nfcSupportBadge.className = 'support-badge supported';
    return true;
  } else {
    nfcSupportBadge.textContent = 'Web NFC غير مدعومة على هذا المتصفح/الجهاز ❌';
    nfcSupportBadge.className = 'support-badge unsupported';
    showStatus('Web NFC غير مدعومة هنا. استخدم هاتف Android عبر متصفح Google Chrome مع تفعيل NFC.', 'error');
    btnScan.disabled = true;
    return false;
  }
}

function showStatus(message, type = 'info', showLoading = false) {
  statusBox.className = `status-box ${type}`;
  if (showLoading) {
    statusBox.classList.add('active-wait');
    spinner.classList.remove('hidden');
  } else {
    statusBox.classList.remove('active-wait');
    spinner.classList.add('hidden');
  }
  statusMsg.textContent = message;
  statusBox.classList.remove('hidden');
}

// ------------------------------------------------------------------
// 4. Scan, Deep Inspect & Decrypt
// ------------------------------------------------------------------

async function startNFCScan() {
  if (!('NDEFReader' in window)) {
    showStatus('المتصفح لا يدعم تقنية Web NFC.', 'error');
    return;
  }

  try {
    ndefReader = new NDEFReader();
    await ndefReader.scan();
    showStatus('📡 في انتظار تقريب البطاقة... قرّب بطاقة NFC من خلف هاتفك الآن.', 'info', true);

    ndefReader.onreading = async (event) => {
      const { serialNumber, message } = event;
      currentSerial = serialNumber || 'Unknown';
      cardSerial.textContent = currentSerial;

      let rawExtracted = '';
      let allBytes = [];
      let detectedTypes = [];

      for (const record of message.records) {
        detectedTypes.push(record.recordType);
        const textDecoder = new TextDecoder(record.encoding || 'utf-8');
        try {
          rawExtracted += textDecoder.decode(record.data);
        } catch (e) {
          rawExtracted += '[بيانات ثنائية]';
        }

        if (record.data && record.data.buffer) {
          const u8 = new Uint8Array(record.data.buffer);
          allBytes.push(...u8);
        }
      }

      lastRawBytes = new Uint8Array(allBytes.length ? allBytes : new TextEncoder().encode(rawExtracted));
      recordType.textContent = `${detectedTypes.join(', ')} (${lastRawBytes.length} بايت)`;

      // Render Hex Dump
      hexCardContent.value = generateHexDump(lastRawBytes);

      lastRawData = rawExtracted;
      rawCardContent.value = rawExtracted;

      // Enable actions
      btnWrite.disabled = false;
      btnProbeWritable.disabled = false;
      writableStatus.textContent = 'جاهزة للاختبار';
      writableStatus.className = 'badge-plain';

      // Attempt Decryption & Display
      await processAndDisplayData(rawExtracted);
    };

    ndefReader.onreadingerror = () => {
      showStatus('⚠️ تعذر قراءة البطاقة. ثبّت البطاقة خلف الهاتف لثانية إضافية وأعد المحاولة.', 'error');
    };

  } catch (err) {
    console.error('Scan Error:', err);
    showStatus(`خطأ أثناء بدء المسح: ${err.message || err}`, 'error');
  }
}

async function processAndDisplayData(rawText) {
  const secretKey = secretKeyInput.value.trim();
  const decryptResult = await decryptPayload(rawText, secretKey);

  if (!decryptResult.isEncrypted) {
    encryptionStatusBadge.textContent = 'بيانات عادية (غير مشفرة) 📄';
    encryptionStatusBadge.className = 'badge-plain';
    cardContent.value = rawText;
    showStatus(`✅ تم جلب وقراءة بيانات البطاقة ${currentSerial} بنجاح! يمكنك الآن تعديلها بالأسفل.`, 'success');
    saveToHistory(currentSerial, rawText, 'Plain');
  } else if (decryptResult.plaintext !== null) {
    encryptionStatusBadge.textContent = 'مشفرة وتم فك تشفيرها بنجاح 🔓';
    encryptionStatusBadge.className = 'badge-decrypted';
    cardContent.value = decryptResult.plaintext;
    showStatus(`🎉 تم جلب وفك تشفير محتوى البطاقة بنجاح باستخدام المفتاح السري! يمكنك تعديل القيم الآن.`, 'success');
    saveToHistory(currentSerial, decryptResult.plaintext, 'Decrypted');
  } else {
    encryptionStatusBadge.textContent = 'مشفرة (المفتاح غير متطابق) 🔒';
    encryptionStatusBadge.className = 'badge-encrypted';
    cardContent.value = '⚠️ [محتوى مشفر لا يمكن قراءته بدون المفتاح السري الصحيح]';
    showStatus(`🔒 تم اكتشاف بيانات مشفرة، لكن المفتاح السري الحالي غير متطابق. ألقِ نظرة على تبويب (Hex Dump) أو النص الخام، أو أدخل المفتاح الصحيح واضغط "إعادة فك التشفير".`, 'error');
    switchTab('hex');
  }
}

// ------------------------------------------------------------------
// 5. Probe Writable Capability
// ------------------------------------------------------------------

async function probeWritable() {
  if (!lastRawData && !cardContent.value) {
    showStatus('يرجى مسح بطاقة أولاً لفحص قابليتها للكتابة.', 'info');
    return;
  }

  try {
    showStatus('⚡ جاري فحص قابلية التعديل... قرّب البطاقة لاختبار الكتابة عليها دون تخريب محتواها الحقيقي...', 'info', true);
    
    // We try to write back the current data itself to verify write permissions safely
    const writer = new NDEFReader();
    const probeRecord = {
      recordType: 'text',
      data: lastRawData || cardContent.value
    };

    await writer.write({ records: [probeRecord] });

    writableStatus.textContent = 'قابلة للكتابة والتعديل ✅';
    writableStatus.className = 'badge-decrypted';
    showStatus('🎉 ممتاز! تم التأكد بنجاح من أن البطاقة قابلة للتعديل والكتابة (Writable & Unlocked).', 'success');
  } catch (err) {
    console.error('Probe failed:', err);
    writableStatus.textContent = 'محمية أو مقفولة للقراءة فقط 🔒';
    writableStatus.className = 'badge-encrypted';
    showStatus(`⚠️ فشل اختبار الكتابة: ${err.message || err}. هذا يعني أن البطاقة محمية ببتات القفل (Lock Bits) أو مخصصة للقراءة فقط.`, 'error');
  }
}

// ------------------------------------------------------------------
// 6. Modify, Encrypt & Write Back
// ------------------------------------------------------------------

async function writeNFCTag() {
  const plainText = cardContent.value.trim();
  if (!plainText) {
    showStatus('يرجى كتابة محتوى في حقل البيانات قبل محاولة الحفظ.', 'error');
    return;
  }

  const shouldEncrypt = enableEncryption.checked;
  const secretKey = secretKeyInput.value.trim();

  if (shouldEncrypt && !secretKey) {
    showStatus('يرجى إدخال مفتاح سري لتشفير البيانات أو إلغاء تفعيل خيار التشفير.', 'error');
    return;
  }

  try {
    let textToWrite = plainText;

    if (shouldEncrypt) {
      showStatus('جاري تشفير القيم الجديدة بخوارزمية AES-256-GCM...', 'info');
      textToWrite = await encryptPayload(plainText, secretKey);
      rawCardContent.value = textToWrite;
    }

    const writer = new NDEFReader();
    showStatus('📡 جاهز للتعديل! قرّب البطاقة من ظهر الهاتف لتسجيل البيانات الجديدة عليها...', 'info', true);

    await writer.write({
      records: [
        {
          recordType: 'text',
          data: textToWrite
        }
      ]
    });

    // Update Hex Dump with newly written content
    lastRawBytes = new TextEncoder().encode(textToWrite);
    hexCardContent.value = generateHexDump(lastRawBytes);
    lastRawData = textToWrite;

    writableStatus.textContent = 'تم التعديل والكتابة بنجاح ✅';
    writableStatus.className = 'badge-decrypted';

    showStatus(
      shouldEncrypt
        ? '🎉 تم تشفير وتعديل قيم البطاقة بنجاح! لن يستطيع أحد قراءتها بدون المفتاح السري.'
        : '🎉 تم تعديل وكتابة البيانات الصريحة على البطاقة بنجاح!',
      'success'
    );

    if (currentSerial) {
      saveToHistory(currentSerial, plainText, shouldEncrypt ? 'Encrypted' : 'Plain');
    }

  } catch (err) {
    console.error('Write Error:', err);
    writableStatus.textContent = 'فشل التعديل (محمية) 🔒';
    writableStatus.className = 'badge-encrypted';
    showStatus(`فشلت محاولة التعديل: ${err.message || err}. (تأكد أن البطاقة غير محمية بـ Lock Bits للقراءة فقط)`, 'error');
  }
}

// ------------------------------------------------------------------
// 7. Tabs & UI Navigation
// ------------------------------------------------------------------

function switchTab(tab) {
  tabPlain.classList.remove('active');
  tabHex.classList.remove('active');
  tabRaw.classList.remove('active');
  plainView.classList.add('hidden');
  hexView.classList.add('hidden');
  rawView.classList.add('hidden');

  if (tab === 'plain') {
    tabPlain.classList.add('active');
    plainView.classList.remove('hidden');
  } else if (tab === 'hex') {
    tabHex.classList.add('active');
    hexView.classList.remove('hidden');
  } else if (tab === 'raw') {
    tabRaw.classList.add('active');
    rawView.classList.remove('hidden');
  }
}

tabPlain.addEventListener('click', () => switchTab('plain'));
tabHex.addEventListener('click', () => switchTab('hex'));
tabRaw.addEventListener('click', () => switchTab('raw'));

btnProbeWritable.addEventListener('click', probeWritable);

btnDecryptManual.addEventListener('click', async () => {
  if (!lastRawData) {
    showStatus('لم يتم مسح أي بطاقة بعد لفك تشفيرها.', 'info');
    return;
  }
  await processAndDisplayData(lastRawData);
  switchTab('plain');
});

btnToggleKey.addEventListener('click', () => {
  if (secretKeyInput.type === 'password') {
    secretKeyInput.type = 'text';
    btnToggleKey.textContent = '🔒';
  } else {
    secretKeyInput.type = 'password';
    btnToggleKey.textContent = '👁️';
  }
});

btnQuickSample.addEventListener('click', () => {
  const sampleData = JSON.stringify({
    cardId: "TAG-" + Math.floor(100000 + Math.random() * 900000),
    owner: "أحمد خليل",
    role: "Admin & Developer",
    credits: 1000,
    status: "ACTIVE",
    lastModified: new Date().toISOString().split('T')[0]
  }, null, 2);

  cardContent.value = sampleData;
  btnWrite.disabled = false;
  switchTab('plain');
  showStatus('تم تعبئة نموذج بيانات ذكي. يمكنك تعديل أي قيمة ثم الضغط على "حفظ وكتابة التعديل".', 'info');
});

btnClear.addEventListener('click', () => {
  cardContent.value = '';
  rawCardContent.value = '';
  hexCardContent.value = '';
  lastRawData = '';
  lastRawBytes = new Uint8Array(0);
  cardSerial.textContent = 'لم يتم المسح بعد';
  recordType.textContent = '-';
  writableStatus.textContent = 'لم تفحص بعد';
  writableStatus.className = 'badge-plain';
  encryptionStatusBadge.textContent = 'غير مفحوص';
  encryptionStatusBadge.className = 'badge-plain';
  btnWrite.disabled = true;
  btnProbeWritable.disabled = true;
  showStatus('تم تفريغ المحرر.', 'info');
});

// ------------------------------------------------------------------
// 8. History Management
// ------------------------------------------------------------------

let currentFilter = 'all'; // 'all' or 'starred'

function getHistory() {
  try {
    return JSON.parse(localStorage.getItem(STORAGE_KEY)) || [];
  } catch (e) {
    return [];
  }
}

function saveToHistory(serial, content, status) {
  const history = getHistory();
  const existingIndex = history.findIndex(item => item.serial === serial);
  const now = new Date().toLocaleTimeString('ar-EG', { hour: '2-digit', minute: '2-digit' });
  const isStarred = existingIndex > -1 ? (history[existingIndex].isStarred || false) : false;

  const entry = {
    serial,
    content,
    status,
    isStarred,
    time: now
  };

  if (existingIndex > -1) {
    history[existingIndex] = entry;
  } else {
    history.unshift(entry);
  }

  if (history.length > 25) history.pop();
  localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
  renderHistory();
}

function toggleStar(idx, event) {
  if (event) event.stopPropagation();
  const history = getHistory();
  if (history[idx]) {
    history[idx].isStarred = !history[idx].isStarred;
    localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
    renderHistory();
    showStatus(history[idx].isStarred ? '⭐ تم تمييز البطاقة وإضافتها لقائمة المهم!' : 'تمت إزالة البطاقة من قائمة المهم.', 'info');
  }
}

function renderHistory() {
  const history = getHistory();
  const starredCountElem = document.getElementById('starredCount');
  const starredCount = history.filter(item => item.isStarred).length;
  if (starredCountElem) starredCountElem.textContent = starredCount;

  const filtered = currentFilter === 'starred' 
    ? history.map((item, idx) => ({ item, originalIdx: idx })).filter(x => x.item.isStarred)
    : history.map((item, idx) => ({ item, originalIdx: idx }));

  if (filtered.length === 0) {
    historyList.innerHTML = currentFilter === 'starred'
      ? '<p class="empty-state">لا توجد بطاقات مميزة بنجمة ⭐ في خانة المهم بعد.<br><small>اضغط على النجمة بجوار أي بطاقة لإضافتها هنا.</small></p>'
      : '<p class="empty-state">لا يوجد بطاقات مسجلة حتى الآن.</p>';
    return;
  }

  historyList.innerHTML = filtered.map(({ item, originalIdx }) => `
    <div class="history-item" onclick="loadFromHistory(${originalIdx})">
      <div class="history-info">
        <span class="history-uid">UID: ${item.serial} [${item.status || 'Data'}]</span>
        <span class="history-text">${item.content || '(فارغ)'}</span>
      </div>
      <div class="history-right">
        <div class="history-time">${item.time}</div>
        <button class="btn-star ${item.isStarred ? 'starred' : ''}" title="${item.isStarred ? 'إزالة من المهم' : 'إضافة للمهم'}" onclick="toggleStar(${originalIdx}, event)">
          ${item.isStarred ? '★' : '☆'}
        </button>
      </div>
    </div>
  `).join('');
}

window.toggleStar = toggleStar;

window.loadFromHistory = function(idx) {
  const history = getHistory();
  const item = history[idx];
  if (item) {
    cardSerial.textContent = item.serial;
    cardContent.value = item.content;
    currentSerial = item.serial;
    btnWrite.disabled = false;
    btnProbeWritable.disabled = false;
    switchTab('plain');
    showStatus(`تم تحميل بيانات البطاقة ${item.serial} في المحرر.`, 'info');
  }
};

const filterAllBtn = document.getElementById('filterAllCards');
const filterStarredBtn = document.getElementById('filterStarredCards');

if (filterAllBtn && filterStarredBtn) {
  filterAllBtn.addEventListener('click', () => {
    currentFilter = 'all';
    filterAllBtn.classList.add('active');
    filterStarredBtn.classList.remove('active');
    renderHistory();
  });

  filterStarredBtn.addEventListener('click', () => {
    currentFilter = 'starred';
    filterStarredBtn.classList.add('active');
    filterAllBtn.classList.remove('active');
    renderHistory();
  });
}

btnClearHistory.addEventListener('click', () => {
  if (confirm('هل أنت متأكد من مسح سجل البطاقات؟')) {
    localStorage.removeItem(STORAGE_KEY);
    renderHistory();
    showStatus('تم مسح السجل.', 'info');
  }
});

// ------------------------------------------------------------------
// 9. مسح وفرمتة شريحة البطاقة تماماً مع تحذير شديد الخطورة ⚠️
// ------------------------------------------------------------------

async function wipeNFCTag() {
  if (!('NDEFReader' in window)) {
    showStatus('المتصفح لا يدعم تقنية Web NFC.', 'error');
    return;
  }

  const userConfirmed = confirm(
    "⚠️ تحذير أمني شديد الخطورة!\n\n" +
    "هل أنت متأكد تماماً من رغبتك في مسح وفرمتة شريحة البطاقة نهائياً وتصفيرها؟\n\n" +
    "• سيتم تصفير جميع البيانات والمحتويات المشفرة والمعرفات نهائياً.\n" +
    "• لا يمكن استرجاع البيانات الممسوحة بعد إتمام العملية.\n\n" +
    "اضغط (موافق / OK) لتأكيد المسح والفرمتة، أو (إلغاء / Cancel) للتراجع."
  );

  if (!userConfirmed) {
    showStatus('تم إلغاء عملية مسح وفرمتة البطاقة.', 'info');
    return;
  }

  try {
    showStatus('⚠️ قرّب البطاقة الآن من خلف هاتفك لمسحها وفرمتتها بالكامل وتصفيرها...', 'warning', true);
    const ndef = new NDEFReader();
    await ndef.write({ records: [{ recordType: "text", data: "" }] });

    cardContent.value = '';
    rawCardContent.value = '';
    hexCardContent.value = '';
    lastRawData = '';
    lastRawBytes = new Uint8Array(0);
    writableStatus.textContent = 'تم المسح والتصفير ✅';
    writableStatus.className = 'badge-decrypted';

    showStatus('🎉 تم بنجاح مسح وفرمتة شريحة البطاقة بالكامل وتصفيرها! أصبحت فارغة تماماً.', 'success');
    alert('🎉 نجحت العملية: تم مسح وتصفير شريحة البطاقة بالكامل وأصبحت جاهزة لأي استخدام جديد.');
  } catch (err) {
    console.error('Wipe Error:', err);
    showStatus(`فشلت محاولة المسح: ${err.message || err}. (تأكد أن البطاقة غير محمية بـ Lock Bits للقراءة فقط)`, 'error');
  }
}

// Event Listeners
btnScan.addEventListener('click', startNFCScan);
btnWrite.addEventListener('click', writeNFCTag);
if (btnWipeTag) btnWipeTag.addEventListener('click', wipeNFCTag);

// Initialize
checkNFCSupport();
renderHistory();

