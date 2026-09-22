import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart' as encrypt_pkg;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:local_auth/local_auth.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NFCCardVaultApp());
}

// ---------------------------------------------------------------------------
// 1. نموذج بيانات البطاقة الشامل (Deep Card Model)
// ---------------------------------------------------------------------------
class SavedCard {
  String id;
  String name;
  String category;
  String uid;
  String chipType;
  int capacityBytes;
  String standard; // مثل ISO 14443-A أو ISO 14443-4
  String atqa;     // Answer to Request A
  String sak;      // Select Acknowledge
  String techList; // قائمة التقنيات المدعومة
  String hexDump;  // التفريغ الست عشري الكامل
  String content;  // المحتوى المفكوك أو القابل للتعديل
  bool isEncrypted;
  bool isActiveForTap; // هل هي الكارت الذي يبثه الموبايل حالياً؟
  bool isStarred;      // هل البطاقة مميزة بنجمة (المهمة)؟
  String originalCipherScheme; // نوع التشفير الأصلي (مثل AES-256-CBC أو Custom Key)
  String secretKeyUsed;        // المفتاح السري المستخدم للتشفير الأصلي
  String rawCipherPayload;     // النص المشفر الفعلي المعاد إنتاجه
  String date;

  SavedCard({
    required this.id,
    required this.name,
    required this.category,
    required this.uid,
    this.chipType = 'NTAG215 / NFC Type 2',
    this.capacityBytes = 504,
    this.standard = 'ISO 14443-3A',
    this.atqa = '00 44',
    this.sak = '00',
    this.techList = 'NfcA, Ndef',
    this.hexDump = '',
    required this.content,
    this.isEncrypted = false,
    this.isActiveForTap = false,
    this.isStarred = false,
    this.originalCipherScheme = 'AES-256-CBC (NDEF)',
    this.secretKeyUsed = 'MySecretPassphrase123',
    this.rawCipherPayload = '',
    required this.date,
  });

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'category': category,
        'uid': uid,
        'chipType': chipType,
        'capacityBytes': capacityBytes,
        'standard': standard,
        'atqa': atqa,
        'sak': sak,
        'techList': techList,
        'hexDump': hexDump,
        'content': content,
        'isEncrypted': isEncrypted,
        'isActiveForTap': isActiveForTap,
        'isStarred': isStarred,
        'originalCipherScheme': originalCipherScheme,
        'secretKeyUsed': secretKeyUsed,
        'rawCipherPayload': rawCipherPayload,
        'date': date,
      };

  factory SavedCard.fromMap(Map<String, dynamic> map) => SavedCard(
        id: map['id'] ?? '',
        name: map['name'] ?? 'بطاقة بدون اسم',
        category: map['category'] ?? 'عام',
        uid: map['uid'] ?? 'UNKNOWN',
        chipType: map['chipType'] ?? 'NFC Standard Tag',
        capacityBytes: map['capacityBytes'] ?? 504,
        standard: map['standard'] ?? 'ISO 14443-3A',
        atqa: map['atqa'] ?? '00 44',
        sak: map['sak'] ?? '00',
        techList: map['techList'] ?? 'NfcA, Ndef',
        hexDump: map['hexDump'] ?? '',
        content: map['content'] ?? '',
        isEncrypted: map['isEncrypted'] ?? false,
        isActiveForTap: map['isActiveForTap'] ?? false,
        isStarred: map['isStarred'] ?? false,
        originalCipherScheme: map['originalCipherScheme'] ?? 'AES-256-CBC (NDEF)',
        secretKeyUsed: map['secretKeyUsed'] ?? 'MySecretPassphrase123',
        rawCipherPayload: map['rawCipherPayload'] ?? '',
        date: map['date'] ?? '',
      );
}

class AccessLog {
  final String cardName;
  final String uid;
  final String action;
  final String timestamp;
  final bool success;

  AccessLog({
    required this.cardName,
    required this.uid,
    required this.action,
    required this.timestamp,
    this.success = true,
  });

  Map<String, dynamic> toMap() => {
        'cardName': cardName,
        'uid': uid,
        'action': action,
        'timestamp': timestamp,
        'success': success,
      };

  factory AccessLog.fromMap(Map<String, dynamic> map) => AccessLog(
        cardName: map['cardName'] ?? '',
        uid: map['uid'] ?? '',
        action: map['action'] ?? '',
        timestamp: map['timestamp'] ?? '',
        success: map['success'] ?? true,
      );
}

// ---------------------------------------------------------------------------
// 2. تطبيق Flutter الرئيسي
// ---------------------------------------------------------------------------
class NFCCardVaultApp extends StatelessWidget {
  const NFCCardVaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'محفظة ومفتاح NFC الذكي',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        useMaterial3: true,
        primaryColor: const Color(0xFF38BDF8),
        scaffoldBackgroundColor: const Color(0xFF0B1329),
        cardColor: const Color(0xFF17223B),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF38BDF8),
          secondary: Color(0xFF10B981),
          surface: Color(0xFF17223B),
        ),
        fontFamily: 'Roboto',
      ),
      home: const NFCHomeScreen(),
    );
  }
}

class NFCHomeScreen extends StatefulWidget {
  const NFCHomeScreen({super.key});

  @override
  State<NFCHomeScreen> createState() => _NFCHomeScreenState();
}

class _NFCHomeScreenState extends State<NFCHomeScreen> with SingleTickerProviderStateMixin {
  int _currentTab = 0;
  List<SavedCard> _savedCards = [];
  List<AccessLog> _accessLogs = [];
  String _selectedFilter = 'الكل'; // 'الكل', 'المهم ⭐', 'العمل', 'المنزل'

  bool _isNfcAvailable = false;
  bool _isSessionActive = false;
  bool _isBiometricEnabled = false;
  bool _isAuthenticated = true;
  String _status = 'جاهز لقراءة أو تعديل أو عكس البطاقات';

  final LocalAuthentication _localAuth = LocalAuthentication();
  final String _magicHeader = 'ENC:v1:';
  final String _defaultSecretKey = 'MySecretPassphrase123';

  @override
  void initState() {
    super.initState();
    _checkNfcAvailability();
    _loadData();
  }

  Future<void> _checkNfcAvailability() async {
    bool isAvailable = await NfcManager.instance.isAvailable();
    setState(() => _isNfcAvailable = isAvailable);
  }

  Future<void> _loadData() async {
    final prefs = await SharedPreferences.getInstance();

    final cardsData = prefs.getString('saved_nfc_cards_vault_v3');
    if (cardsData != null) {
      try {
        final List<dynamic> list = jsonDecode(cardsData);
        _savedCards = list.map((e) => SavedCard.fromMap(e)).toList();
      } catch (_) {}
    } else {
      _savedCards = [
        SavedCard(
          id: 'card_1',
          name: 'باب المكتب الرئيسي',
          category: 'العمل',
          uid: '4A:7C:12:F3',
          chipType: 'NXP NTAG215',
          capacityBytes: 504,
          standard: 'ISO 14443-3A',
          atqa: '00 44',
          sak: '00',
          techList: 'NfcA, Ndef',
          hexDump: '0000:  4A 7C 12 F3 20 53 45 43  2D 38 38 34 32 00 00 00  |J|.. SEC-8842...|',
          content: '{"doorId": "MAIN_OFFICE", "authCode": "SEC-8842", "uid": "4A:7C:12:F3"}',
          isEncrypted: true,
          isActiveForTap: true,
          isStarred: true, // مميزة بنجمة في خانة المهم
          date: '2026-09-22',
        ),
        SavedCard(
          id: 'card_2',
          name: 'بوابة الجراج والفيلا',
          category: 'المنزل',
          uid: '04:88:E2:AA',
          chipType: 'Mifare Classic 1K',
          capacityBytes: 1024,
          standard: 'ISO 14443-3A (Mifare)',
          atqa: '00 04',
          sak: '08',
          techList: 'MifareClassic, NfcA',
          hexDump: '0000:  04 88 E2 AA 47 41 54 45  2D 50 41 53 53 2D 34 34  |....GATE-PASS-44|',
          content: 'GATE-PASS-KEY-4491-VILLA',
          isEncrypted: false,
          isActiveForTap: false,
          isStarred: false,
          date: '2026-09-22',
        )
      ];
      _persistCards();
      _syncActiveEmulationCard();
    }

    final logsData = prefs.getString('saved_nfc_access_logs');
    if (logsData != null) {
      try {
        final List<dynamic> list = jsonDecode(logsData);
        _accessLogs = list.map((e) => AccessLog.fromMap(e)).toList();
      } catch (_) {}
    }
    setState(() {});
  }

  Future<void> _persistCards() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_nfc_cards_vault_v3', jsonEncode(_savedCards.map((e) => e.toMap()).toList()));
    _syncActiveEmulationCard();
  }

  // تمييز/إلغاء تمييز البطاقة بنجمة في خانة المهم
  void _toggleStarCard(SavedCard card) {
    setState(() {
      card.isStarred = !card.isStarred;
    });
    _persistCards();
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        duration: const Duration(seconds: 1),
        backgroundColor: card.isStarred ? const Color(0xFF0F766E) : const Color(0xFF334155),
        content: Text(card.isStarred
            ? '⭐ تمت إضافة "${card.name}" إلى خانة المهم'
            : 'تمت إزالة "${card.name}" من خانة المهم'),
      ),
    );
  }

  // مزامنة الكارت النشط مع خدمة الـ HCE الأندرويد لتبثه عند التلامس
  Future<void> _syncActiveEmulationCard() async {
    final prefs = await SharedPreferences.getInstance();
    SavedCard? active;
    try {
      active = _savedCards.firstWhere((c) => c.isActiveForTap);
    } catch (_) {
      if (_savedCards.isNotEmpty) active = _savedCards.first;
    }

    if (active != null) {
      // حفظ بيانات الكارت في SharedPreferences ليقرأها MyNfcHostApduService
      final emulationPayload = jsonEncode({
        "uid": active.uid,
        "name": active.name,
        "payload": active.content,
      });
      await prefs.setString('active_emulation_card', emulationPayload);
    }
  }

  Future<void> _addAccessLog(String cardName, String uid, String action, {bool success = true}) async {
    final now = DateTime.now();
    final timeStr = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')} - ${now.year}/${now.month}/${now.day}';
    final newLog = AccessLog(cardName: cardName, uid: uid, action: action, timestamp: timeStr, success: success);

    setState(() {
      _accessLogs.insert(0, newLog);
      if (_accessLogs.length > 50) _accessLogs.removeLast();
    });

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('saved_nfc_access_logs', jsonEncode(_accessLogs.map((e) => e.toMap()).toList()));
  }

  // ---------------------------------------------------------------------------
  // 3. تحليل وتفريغ الـ Hex Dump الشامل لكشف جميع بايتات البطاقة
  // ---------------------------------------------------------------------------
  String _generateFullHexDump(List<int> bytes) {
    if (bytes.isEmpty) return 'لا توجد بيانات ثنائية متاحة.';
    final buffer = StringBuffer();
    for (int i = 0; i < bytes.length; i += 16) {
      final end = (i + 16 < bytes.length) ? i + 16 : bytes.length;
      final chunk = bytes.sublist(i, end);

      final offset = i.toRadixString(16).padLeft(4, '0').toUpperCase();
      final hexPart = chunk.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ').padRight(48);

      final asciiPart = chunk.map((b) => (b >= 32 && b <= 126) ? String.fromCharCode(b) : '.').join();
      buffer.writeln('$offset:  $hexPart |$asciiPart|');
    }
    return buffer.toString();
  }

  // ---------------------------------------------------------------------------
  // 4. قراءة جميع المعلومات العميقة والمخفية في البطاقة (Deep Scan)
  // ---------------------------------------------------------------------------
  void _startNfcDeepScanAndSave() async {
    if (!_isNfcAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC غير مفعل في الهاتف!')));
      return;
    }

    setState(() {
      _isSessionActive = true;
      _status = '📡 قرّب البطاقة لقراءة جميع المعلومات العميقة والـ Hex والمحتوى...';
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          Map<String, dynamic> tagData = tag.data;

          // 1. استخراج الـ UID
          String serial = 'Unknown';
          String atqaStr = '00 44';
          String sakStr = '00';
          String standardStr = 'ISO 14443-3A';
          List<String> technologies = [];

          if (tagData.containsKey('isodep')) {
            serial = (tagData['isodep']['identifier'] as List).map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
            standardStr = 'ISO 14443-4 (Smart Card)';
            technologies.add('IsoDep');
          }
          if (tagData.containsKey('nfca')) {
            if (serial == 'Unknown') {
              serial = (tagData['nfca']['identifier'] as List).map((e) => e.toRadixString(16).padLeft(2, '0')).join(':');
            }
            if (tagData['nfca']['atqa'] != null) {
              atqaStr = (tagData['nfca']['atqa'] as List).map((e) => e.toRadixString(16).padLeft(2, '0')).join(' ');
            }
            if (tagData['nfca']['sak'] != null) {
              sakStr = (tagData['nfca']['sak'] as int).toRadixString(16).padLeft(2, '0');
            }
            technologies.add('NfcA');
          }
          if (tagData.containsKey('mifareclassic')) technologies.add('MifareClassic');
          if (tagData.containsKey('mifareultralight')) technologies.add('MifareUltralight');
          if (ndef != null) technologies.add('NDEF');

          // 2. كشف نوع الشريحة والذاكرة بدقة
          String chipName = 'NFC Standard Tag';
          int maxCap = ndef?.maxSize ?? 504;
          if (tagData.containsKey('mifareclassic')) {
            chipName = 'NXP Mifare Classic 1K';
            maxCap = 1024;
          } else if (tagData.containsKey('mifareultralight')) {
            chipName = 'NXP NTAG213 / Ultralight';
            maxCap = 144;
          } else if (tagData.containsKey('isodep')) {
            chipName = 'Mifare DESFire / Smart Card';
            maxCap = 2048;
          } else if (maxCap >= 800) {
            chipName = 'NXP NTAG216 (High Memory)';
          } else if (maxCap >= 450) {
            chipName = 'NXP NTAG215 (Standard)';
          }

          // 3. قراءة كافة بايتات ومحتويات الـ NDEF والسجلات
          List<int> allBytes = [];
          String extractedContent = '';
          if (ndef != null && ndef.cachedMessage != null) {
            for (var record in ndef.cachedMessage!.records) {
              allBytes.addAll(record.payload);
              try {
                if (record.typeNameFormat == NdefTypeNameFormat.nfcWellknown && record.payload.isNotEmpty) {
                  int langLen = record.payload[0] & 0x3F;
                  extractedContent += utf8.decode(record.payload.sublist(langLen + 1));
                } else {
                  extractedContent += utf8.decode(record.payload);
                }
              } catch (_) {
                extractedContent += utf8.decode(record.payload, allowMalformed: true);
              }
            }
          }

          if (allBytes.isEmpty) {
            // إضافة بايتات الـ UID لتوليد تفريغ أولي
            allBytes = serial.split(':').map((s) => int.tryParse(s, radix: 16) ?? 0).toList();
          }

          final fullHex = _generateFullHexDump(allBytes);

          NfcManager.instance.stopSession();
          HapticFeedback.mediumImpact();

          setState(() => _isSessionActive = false);

          final newCard = SavedCard(
            id: 'card_${DateTime.now().millisecondsSinceEpoch}',
            name: 'كارت مسحوب (${serial.toUpperCase()})',
            category: 'العمل',
            uid: serial.toUpperCase(),
            chipType: chipName,
            capacityBytes: maxCap,
            standard: standardStr,
            atqa: atqaStr,
            sak: sakStr,
            techList: technologies.join(', '),
            hexDump: fullHex,
            content: extractedContent.isNotEmpty ? extractedContent : 'UID: $serial - Ready to emulate',
            isEncrypted: extractedContent.startsWith(_magicHeader),
            date: DateTime.now().toString().split(' ')[0],
          );

          await _addAccessLog(newCard.name, newCard.uid, 'قراءة وسحب جميع المعلومات');
          _openEditCardDialog(isNew: true, card: newCard);
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: e.toString());
          setState(() => _isSessionActive = false);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 5. فحص إمكانية الكتابة والتعديل على البطاقة فيزيائياً (Probe Writable)
  // ---------------------------------------------------------------------------
  void _probeCardWritable(SavedCard card) async {
    if (!_isNfcAvailable) return;

    setState(() {
      _isSessionActive = true;
      _status = '⚡ قرّب البطاقة لفحص هل تقبل التعديل والكتابة أم محمية...';
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          bool canWrite = ndef != null && ndef.isWritable;
          NfcManager.instance.stopSession();
          HapticFeedback.mediumImpact();

          setState(() {
            _isSessionActive = false;
            _status = canWrite
                ? '🎉 ممتازة! البطاقة مفتوحة وقابلة للكتابة والتعديل بنجاح ✅'
                : '⚠️ هذه البطاقة محمية ببتات القفل ومخصصة للقراءة فقط 🔒';
          });

          await _addAccessLog(card.name, card.uid, canWrite ? 'فحص: قابلة للتعديل' : 'فحص: محمية', success: canWrite);

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: canWrite ? const Color(0xFF059669) : Colors.red.shade800,
              content: Text(canWrite
                  ? '🎉 البطاقة مفتوحة وتقبل الكتابة والتعديل المباشر!'
                  : '⚠️ البطاقة محمية ومقفولة للقراءة فقط. يمكنك عكسها من الموبايل أو نسخها على ملصق.'),
            ),
          );
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: e.toString());
          setState(() => _isSessionActive = false);
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. كتابة وتعديل البيانات فعلياً على شريحة البطاقة أو ملصق الجراب
  // ---------------------------------------------------------------------------
  void _writeCardToPhysicalTag(SavedCard card, bool encrypt) async {
    if (!_isNfcAvailable) return;

    setState(() {
      _isSessionActive = true;
      _status = '📡 قرّب البطاقة أو ملصق الجراب الآن لكتابة "${card.name}" عليها...';
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          if (ndef == null || !ndef.isWritable) {
            NfcManager.instance.stopSession(errorMessage: 'Card locked');
            setState(() {
              _isSessionActive = false;
              _status = 'فشلت الكتابة: هذه البطاقة محمية أو مقفولة للقراءة فقط 🔒.';
            });
            await _addAccessLog(card.name, card.uid, 'فشل الكتابة (محمية)', success: false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('❌ فشلت الكتابة: البطاقة محمية للقراءة فقط. يمكنك عكسها من الموبايل بدلاً من ذلك.'),
              ),
            );
            return;
          }

          String textToWrite = card.content;
          if (encrypt) {
            textToWrite = _encryptData(card.content, _defaultSecretKey);
          }

          NdefMessage message = NdefMessage([
            NdefRecord.createText(textToWrite),
          ]);

          await ndef.write(message);
          NfcManager.instance.stopSession();
          HapticFeedback.heavyImpact();

          setState(() {
            _isSessionActive = false;
            _status = '🎉 تم بنجاح كتابة وتعديل بيانات "${card.name}" على الشريحة!';
          });

          await _addAccessLog(card.name, card.uid, 'كتابة وتعديل على الشريحة');
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              backgroundColor: const Color(0xFF059669),
              content: Text('🎉 تم كتابة التعديل بنجاح على الشريحة!'),
            ),
          );
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: e.toString());
          setState(() {
            _isSessionActive = false;
            _status = 'خطأ أثناء الكتابة: $e';
          });
        }
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6.ب. مسح وفرمتة البطاقة تماماً وتصفيرها مع تحذير شديد الخطورة ⚠️
  // ---------------------------------------------------------------------------
  void _confirmAndWipePhysicalTag({SavedCard? card}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Colors.red, width: 1.8),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red, size: 30),
              SizedBox(width: 8),
              Text('⚠️ تحذير شديد الخطورة!', style: TextStyle(color: Colors.red, fontSize: 18, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                card != null
                    ? 'هل أنت متأكد تماماً من رغبتك في مسح وفرمتة بطاقة "${card.name}" نهائياً؟'
                    : 'هل أنت متأكد من رغبتك في مسح وفرمتة بطاقة الـ NFC نهائياً؟',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.withOpacity(0.4)),
                ),
                child: const Text(
                  '🚨 تنبيه: هذا الإجراء سيقوم بتصفير بايتات الشريحة وحذف كافة البيانات المشفرة والمعرفات والمحتويات نهائياً! لن تتمكن من استرجاع البيانات الممسوحة مطلقاً.',
                  style: TextStyle(color: Color(0xFFFCA5A5), fontSize: 12, height: 1.4),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء وتراجع', style: TextStyle(color: Colors.grey, fontSize: 14)),
            ),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade700,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              icon: const Icon(Icons.delete_forever, color: Colors.white, size: 20),
              label: const Text('نعم، افرمِت وامسح البطاقة الآن 🗑️', style: TextStyle(fontWeight: FontWeight.bold)),
              onPressed: () {
                Navigator.pop(dialogCtx);
                _startWipePhysicalTagSession(card);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _startWipePhysicalTagSession(SavedCard? card) async {
    if (!_isNfcAvailable) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('NFC غير مفعل في الهاتف!')));
      return;
    }

    setState(() {
      _isSessionActive = true;
      _status = '⚠️ قرّب البطاقة الآن من ظهر الهاتف لفرمتتها ومسح كافة بياناتها وتصفيرها...';
    });

    NfcManager.instance.startSession(
      onDiscovered: (NfcTag tag) async {
        try {
          var ndef = Ndef.from(tag);
          if (ndef == null || !ndef.isWritable) {
            NfcManager.instance.stopSession(errorMessage: 'Card locked');
            setState(() {
              _isSessionActive = false;
              _status = 'فشل المسح: البطاقة محمية ضد الكتابة للقراءة فقط 🔒';
            });
            await _addAccessLog(card?.name ?? 'بطاقة خارجية', card?.uid ?? 'UNKNOWN', 'فشل المسح (البطاقة مقفولة)', success: false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                backgroundColor: Colors.red,
                content: Text('❌ لا يمكن مسح هذه البطاقة: البطاقة محمية بـ Lock Bits للقراءة فقط.'),
              ),
            );
            return;
          }

          // كتابة سجل NDEF فارغ تماماً لتصفير محتوى البطاقة
          NdefMessage emptyMessage = NdefMessage([
            NdefRecord.createText(''),
          ]);

          await ndef.write(emptyMessage);
          NfcManager.instance.stopSession();
          HapticFeedback.heavyImpact();

          setState(() {
            _isSessionActive = false;
            _status = '🎉 تم بنجاح مسح وفرمتة شريحة البطاقة بالكامل وتصفيرها! ✅';
          });

          await _addAccessLog(card?.name ?? 'بطاقة خارجية', card?.uid ?? 'UNKNOWN', 'مسح وفرمتة البطاقة نهائياً (Wiped)');

          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              backgroundColor: Color(0xFF059669),
              content: Text('🎉 تم بنجاح فرمتة ومسح البطاقة بالكامل! أصبحت فارغة وجاهزة لأي استخدام جديد.'),
            ),
          );
        } catch (e) {
          NfcManager.instance.stopSession(errorMessage: e.toString());
          setState(() {
            _isSessionActive = false;
            _status = 'خطأ أثناء الفرمتة: $e';
          });
        }
      },
    );
  }

  void _confirmDeleteFromVault(SavedCard card) {
    showDialog(
      context: context,
      builder: (dialogCtx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          backgroundColor: const Color(0xFF1E293B),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('حذف من المحفظة', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          content: Text('هل أنت متأكد من حذف بطاقة "${card.name}" من سجل المحفظة؟', style: const TextStyle(color: Colors.white70)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red.shade700),
              onPressed: () {
                Navigator.pop(dialogCtx);
                setState(() => _savedCards.removeWhere((c) => c.id == card.id));
                _persistCards();
                ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم حذف "${card.name}" من المحفظة.')));
              },
              child: const Text('حذف', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 7. نافذة التعديل الشامل لمعلومات البطاقة ومحتواها
  // ---------------------------------------------------------------------------
  void _openEditCardDialog({required bool isNew, required SavedCard card}) {
    final nameCtrl = TextEditingController(text: card.name);
    final categoryCtrl = TextEditingController(text: card.category);
    final uidCtrl = TextEditingController(text: card.uid);
    final chipCtrl = TextEditingController(text: card.chipType);
    final capacityCtrl = TextEditingController(text: card.capacityBytes.toString());
    final contentCtrl = TextEditingController(text: card.content);
    final hexCtrl = TextEditingController(text: card.hexDump);
    final secretKeyCtrl = TextEditingController(text: card.secretKeyUsed.isNotEmpty ? card.secretKeyUsed : _defaultSecretKey);
    bool shouldReEncrypt = card.isEncrypted;
    bool starredState = card.isStarred;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: const Color(0xFF17223B),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(22))),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                top: 20,
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Directionality(
                textDirection: TextDirection.rtl,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            isNew ? 'قراءة وسحب بطاقة جديدة' : 'تعديل جميع معلومات البطاقة',
                            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.grey),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // اسم البطاقة
                      TextField(
                        controller: nameCtrl,
                        decoration: InputDecoration(
                          labelText: 'اسم البطاقة / الاستخدام',
                          filled: true,
                          fillColor: const Color(0xFF263859),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // تصنيف الكارت والمعرف UID
                      Row(
                        children: [
                          Expanded(
                            flex: 1,
                            child: DropdownButtonFormField<String>(
                              value: ['العمل', 'المنزل', 'الجراج', 'عام'].contains(categoryCtrl.text) ? categoryCtrl.text : 'عام',
                              dropdownColor: const Color(0xFF17223B),
                              decoration: InputDecoration(
                                labelText: 'التصنيف',
                                filled: true,
                                fillColor: const Color(0xFF263859),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                              items: ['العمل', 'المنزل', 'الجراج', 'عام'].map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
                              onChanged: (val) => setModalState(() => categoryCtrl.text = val ?? 'عام'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            flex: 1,
                            child: TextField(
                              controller: uidCtrl,
                              decoration: InputDecoration(
                                labelText: 'المعرف الفريد (UID)',
                                filled: true,
                                fillColor: const Color(0xFF263859),
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // معلومات العتاد والذاكرة المقروءة
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFF111A31),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('معلومات العتاد المقروءة:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade400)),
                            const SizedBox(height: 4),
                            Text('• نوع الشريحة: ${card.chipType}', style: const TextStyle(fontSize: 12, color: Color(0xFF38BDF8))),
                            Text('• المعيار: ${card.standard}  •  السعة: ${card.capacityBytes} بايت', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                            Text('• ATQA: ${card.atqa}  •  SAK: ${card.sak}  •  التقنيات: ${card.techList}', style: const TextStyle(fontSize: 11, color: Colors.white54)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),

                      // محتوى وقيم البطاقة الداخلية القابلة للتعديل
                      TextField(
                        controller: contentCtrl,
                        maxLines: 3,
                        decoration: InputDecoration(
                          labelText: 'البيانات والمحتوى الداخلي (Payload) - قابل للتعديل',
                          filled: true,
                          fillColor: const Color(0xFF263859),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 10),

                      // معاينة الـ Hex Dump
                      TextField(
                        controller: hexCtrl,
                        maxLines: 3,
                        readOnly: true,
                        style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                        decoration: InputDecoration(
                          labelText: 'تفريغ البايتات الخام (Hex Dump)',
                          filled: true,
                          fillColor: const Color(0xFF111A31),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                      ),
                      const SizedBox(height: 12),

                      // تمييز كبطاقة مهمة بنجمة ⭐
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Row(
                          children: [
                            Icon(Icons.star, color: Colors.amber, size: 20),
                            SizedBox(width: 8),
                            Text('تمييز كبطاقة مهمة ⭐ (إضافة للمهم)', style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                          ],
                        ),
                        subtitle: const Text('تظهر في خانة المهم لسهولة وسرعة الوصول إليها', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        value: starredState,
                        onChanged: (val) => setModalState(() => starredState = val),
                      ),
                      const SizedBox(height: 14),

                      // صندوق إعادة التشفير الأصلي بعد التعديل 🔐
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1E293B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: shouldReEncrypt ? const Color(0xFF10B981) : Colors.white12, width: 1.2),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Row(
                                  children: [
                                    Icon(Icons.lock_reset, color: shouldReEncrypt ? const Color(0xFF10B981) : Colors.grey, size: 22),
                                    const SizedBox(width: 8),
                                    const Text('إعادة التشفير الأصلي بعد التعديل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.white)),
                                  ],
                                ),
                                Switch(
                                  value: shouldReEncrypt,
                                  activeColor: const Color(0xFF10B981),
                                  onChanged: (val) => setModalState(() => shouldReEncrypt = val),
                                ),
                              ],
                            ),
                            if (shouldReEncrypt) ...[
                              const SizedBox(height: 6),
                              Text('نمط التشفير الأصلي: ${card.originalCipherScheme}', style: const TextStyle(fontSize: 11, color: Color(0xFF38BDF8), fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              TextField(
                                controller: secretKeyCtrl,
                                decoration: InputDecoration(
                                  labelText: 'مفتاح التشفير الأصلي (Secret Key)',
                                  hintText: 'أدخل المفتاح لتشفير التعديلات بنفس النمط...',
                                  filled: true,
                                  fillColor: const Color(0xFF111A31),
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                  suffixIcon: IconButton(
                                    icon: const Icon(Icons.refresh, color: Color(0xFF10B981)),
                                    tooltip: 'معاينة التشفير الفوري على الـ Hex Dump',
                                    onPressed: () {
                                      final reEncrypted = _encryptData(contentCtrl.text.trim(), secretKeyCtrl.text.trim());
                                      hexCtrl.text = _generateFullHexDump(utf8.encode(reEncrypted));
                                      setModalState(() {});
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('🔒 تم تطبيق التشفير الأصلي وتحديث الـ Hex Dump فوراً!')),
                                      );
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      const SizedBox(height: 14),

                      // أزرار الحفظ والعكس
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF0284C7),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.save, color: Colors.white),
                        label: const Text('حفظ التعديلات في المحفظة', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () {
                          String finalEncryptedPayload = contentCtrl.text.trim();
                          if (shouldReEncrypt) {
                            finalEncryptedPayload = _encryptData(contentCtrl.text.trim(), secretKeyCtrl.text.trim());
                          }

                          setState(() {
                            card.name = nameCtrl.text.trim();
                            card.category = categoryCtrl.text.trim();
                            card.uid = uidCtrl.text.trim();
                            card.content = contentCtrl.text.trim();
                            card.rawCipherPayload = finalEncryptedPayload;
                            card.isEncrypted = shouldReEncrypt;
                            card.secretKeyUsed = secretKeyCtrl.text.trim();
                            card.isStarred = starredState;
                            if (isNew) _savedCards.add(card);
                          });
                          _persistCards();
                          _addAccessLog(card.name, card.uid, shouldReEncrypt ? 'تعديل وحفظ مشفر أصلياً' : 'تعديل وحفظ الكارت');
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(shouldReEncrypt ? '✅ تم حفظ التعديلات بالتشفير الأصلي بنجاح!' : '✅ تم حفظ التعديلات بنجاح')),
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // زر التفعيل المباشر للعكس من الموبايل
                      ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          backgroundColor: const Color(0xFF0F766E),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.sensors, color: Colors.white),
                        label: const Text('عكس وبث هذا الكارت من الموبايل للقارئ 📡', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.white)),
                        onPressed: () {
                          String finalEncryptedPayload = contentCtrl.text.trim();
                          if (shouldReEncrypt) {
                            finalEncryptedPayload = _encryptData(contentCtrl.text.trim(), secretKeyCtrl.text.trim());
                          }

                          setState(() {
                            card.name = nameCtrl.text.trim();
                            card.category = categoryCtrl.text.trim();
                            card.uid = uidCtrl.text.trim();
                            card.content = contentCtrl.text.trim();
                            card.rawCipherPayload = finalEncryptedPayload;
                            card.isEncrypted = shouldReEncrypt;
                            card.secretKeyUsed = secretKeyCtrl.text.trim();
                            card.isStarred = starredState;
                            if (isNew) _savedCards.add(card);
                            for (var c in _savedCards) {
                              c.isActiveForTap = (c.id == card.id);
                            }
                          });
                          _persistCards();
                          _addAccessLog(card.name, card.uid, 'تفعيل البث والعكس بالتشفير الأصلي');
                          HapticFeedback.mediumImpact();
                          Navigator.pop(ctx);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('📡 الكارت "${card.name}" يبث التعديل المشفر أصلياً عند التلامس!')),
                          );
                        },
                      ),
                      const SizedBox(height: 8),

                      // زر كتابة وتعديل البطاقة فيزيائياً / ملصق الجراب بالتشفير الأصلي
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          side: const BorderSide(color: Color(0xFF10B981)),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.edit_note, color: Color(0xFF10B981)),
                        label: Text(
                          shouldReEncrypt
                              ? 'كتابة التعديل بالشفرة الأصلية على الكارت 🔐'
                              : 'كتابة التعديل على شريحة البطاقة / ملصق الجراب ✍️',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF10B981)),
                        ),
                        onPressed: () {
                          String finalEncryptedPayload = contentCtrl.text.trim();
                          if (shouldReEncrypt) {
                            finalEncryptedPayload = _encryptData(contentCtrl.text.trim(), secretKeyCtrl.text.trim());
                          }

                          card.name = nameCtrl.text.trim();
                          card.category = categoryCtrl.text.trim();
                          card.uid = uidCtrl.text.trim();
                          card.content = contentCtrl.text.trim();
                          card.rawCipherPayload = finalEncryptedPayload;
                          card.isEncrypted = shouldReEncrypt;
                          card.secretKeyUsed = secretKeyCtrl.text.trim();
                          card.isStarred = starredState;
                          if (isNew) _savedCards.add(card);
                          _persistCards();

                          Navigator.pop(ctx);
                          _writeCardToPhysicalTag(card, shouldReEncrypt);
                        },
                      ),
                      const SizedBox(height: 8),

                      // زر فحص هل البطاقة تقبل الكتابة والتعديل
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.amber),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.bolt, color: Colors.amber),
                        label: const Text('فحص هل البطاقة تقبل الكتابة (Test Writable) ⚡', style: TextStyle(fontSize: 13, color: Colors.amber)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _probeCardWritable(card);
                        },
                      ),
                      const SizedBox(height: 8),

                      // زر مسح وفرمتة شريحة البطاقة تماماً مع تحذير ⚠️
                      OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          side: const BorderSide(color: Colors.redAccent),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.delete_forever, color: Colors.redAccent),
                        label: const Text('مسح وفرمتة شريحة البطاقة تماماً ⚠️', style: TextStyle(fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _confirmAndWipePhysicalTag(card: card);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------------------------------------------------------------------------
  // 6. الواجهة وتصميم المحفظة وعكس البطاقة
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    SavedCard? activeCard;
    try {
      activeCard = _savedCards.firstWhere((c) => c.isActiveForTap);
    } catch (_) {
      if (_savedCards.isNotEmpty) activeCard = _savedCards.first;
    }

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('محفظة وعاكس بطاقات NFC', style: TextStyle(fontWeight: FontWeight.bold)),
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF17223B),
          actions: [
            IconButton(
              icon: const Icon(Icons.nfc),
              tooltip: 'قراءة وسحب جميع معلومات البطاقة',
              onPressed: _isSessionActive ? null : _startNfcDeepScanAndSave,
            ),
          ],
        ),
        body: Column(
          children: [
            // بطاقة العكس النشط (التي يبثها الموبايل للقارئ)
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFF0284C7), Color(0xFF0F766E)],
                  begin: Alignment.topRight,
                  end: Alignment.bottomLeft,
                ),
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFF0284C7).withOpacity(0.35),
                    blurRadius: 18,
                    offset: const Offset(0, 6),
                  )
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.sensors, color: Colors.white, size: 26),
                          SizedBox(width: 8),
                          Text('وضع العكس والبث للقارئ (HCE)', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.bold)),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Text('يبث للقارئ بالتلامس 📡', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                      )
                    ],
                  ),
                  const SizedBox(height: 14),
                  Text(
                    activeCard != null ? activeCard.name : 'لا توجد بطاقة نشطة للعكس',
                    style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    activeCard != null
                        ? 'UID المعكوس: ${activeCard.uid}  •  الشريحة: ${activeCard.chipType}'
                        : 'اسحب كارت أو اختر كارت للبدء',
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(8)),
                    child: Text(
                      activeCard != null ? 'المحتوى المُرسل للقارئ: ${activeCard.content}' : '-',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontFamily: 'monospace', color: Colors.lightGreenAccent, fontSize: 11),
                    ),
                  )
                ],
              ),
            ),

            if (_isSessionActive)
              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF17223B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF38BDF8), width: 0.7),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    const SizedBox(width: 12),
                    Expanded(child: Text(_status, style: const TextStyle(fontSize: 13, color: Colors.white))),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('المحفظة (${_savedCards.length})', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Colors.white)),
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0284C7),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    ),
                    onPressed: _startNfcDeepScanAndSave,
                    icon: const Icon(Icons.add, size: 16, color: Colors.white),
                    label: const Text('قراءة كارت جديد', style: TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
            ),

            // شريط تصفية خانات البطاقات (الكل / خانة المهم ⭐ / العمل / المنزل / الجراج)
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  _buildFilterChip('الكل', '${_savedCards.length}'),
                  const SizedBox(width: 8),
                  _buildFilterChip('المهم ⭐', '${_savedCards.where((c) => c.isStarred).length}', isStarredTab: true),
                  const SizedBox(width: 8),
                  _buildFilterChip('العمل', '${_savedCards.where((c) => c.category == 'العمل').length}'),
                  const SizedBox(width: 8),
                  _buildFilterChip('المنزل', '${_savedCards.where((c) => c.category == 'المنزل').length}'),
                  const SizedBox(width: 8),
                  _buildFilterChip('الجراج', '${_savedCards.where((c) => c.category == 'الجراج').length}'),
                ],
              ),
            ),
            const SizedBox(height: 6),

            // قائمة البطاقات المفلترة حسب الخانة
            Expanded(
              child: Builder(
                builder: (context) {
                  final filteredCards = _savedCards.where((card) {
                    if (_selectedFilter == 'المهم ⭐') return card.isStarred;
                    if (_selectedFilter == 'العمل') return card.category == 'العمل';
                    if (_selectedFilter == 'المنزل') return card.category == 'المنزل';
                    if (_selectedFilter == 'الجراج') return card.category == 'الجراج';
                    return true;
                  }).toList();

                  if (filteredCards.isEmpty) {
                    if (_selectedFilter == 'المهم ⭐') {
                      return Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.star_border, size: 54, color: Colors.amber),
                            const SizedBox(height: 12),
                            const Text('خانة المهم فارغة حالياً ⭐', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                            const SizedBox(height: 6),
                            const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                'اضغط على أيقونة النجمة ⭐ بجوار أي كارت لإضافته للمهم والوصول إليه بسرعة.',
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                            ),
                          ],
                        ),
                      );
                    } else {
                      return const Center(
                        child: Text('لا توجد بطاقات في هذا التصنيف', style: TextStyle(color: Colors.grey)),
                      );
                    }
                  }

                  return ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: filteredCards.length,
                    itemBuilder: (context, index) {
                      final card = filteredCards[index];
                      return Card(
                        color: const Color(0xFF17223B),
                        margin: const EdgeInsets.only(bottom: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                          side: BorderSide(
                            color: card.isActiveForTap ? const Color(0xFF38BDF8) : Colors.white10,
                            width: card.isActiveForTap ? 1.5 : 0.6,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          leading: Stack(
                            alignment: Alignment.bottomRight,
                            children: [
                              CircleAvatar(
                                backgroundColor: card.isActiveForTap ? const Color(0xFF0284C7) : const Color(0xFF263859),
                                child: Icon(
                                  card.category == 'العمل'
                                      ? Icons.business
                                      : card.category == 'المنزل'
                                          ? Icons.home
                                          : Icons.credit_card,
                                  color: Colors.white,
                                ),
                              ),
                              if (card.isStarred)
                                const CircleAvatar(
                                  radius: 8,
                                  backgroundColor: Colors.amber,
                                  child: Icon(Icons.star, size: 10, color: Colors.black),
                                ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  card.name,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: card.isActiveForTap ? const Color(0xFF10B981).withOpacity(0.2) : const Color(0xFF38BDF8).withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  card.isActiveForTap ? 'المعكوس حالياً 📡' : card.chipType,
                                  style: TextStyle(
                                    color: card.isActiveForTap ? const Color(0xFF10B981) : const Color(0xFF38BDF8),
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 4),
                              Text('UID: ${card.uid}  •  ${card.standard} (${card.capacityBytes}B)', style: const TextStyle(color: Colors.grey, fontSize: 11)),
                              const SizedBox(height: 2),
                              Text(
                                card.content,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(color: Colors.white60, fontSize: 11),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              // زر النجمة للإضافة/الإزالة من خانة المهم فوراً
                              IconButton(
                                icon: Icon(
                                  card.isStarred ? Icons.star : Icons.star_border,
                                  color: card.isStarred ? Colors.amber : Colors.grey,
                                  size: 24,
                                ),
                                tooltip: card.isStarred ? 'إزالة من المهم' : 'إضافة إلى المهم ⭐',
                                onPressed: () => _toggleStarCard(card),
                              ),
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert, color: Colors.grey),
                                color: const Color(0xFF17223B),
                                onSelected: (value) {
                                  if (value == 'edit') {
                                    _openEditCardDialog(isNew: false, card: card);
                                  } else if (value == 'star') {
                                    _toggleStarCard(card);
                                  } else if (value == 'write') {
                                    _writeCardToPhysicalTag(card, card.isEncrypted);
                                  } else if (value == 'probe') {
                                    _probeCardWritable(card);
                                  } else if (value == 'set_active') {
                                    setState(() {
                                      for (var c in _savedCards) {
                                        c.isActiveForTap = (c.id == card.id);
                                      }
                                    });
                                    _persistCards();
                                    _addAccessLog(card.name, card.uid, 'تفعيل البث والعكس من الموبايل');
                                    HapticFeedback.lightImpact();
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(content: Text('📡 تم ضبط "${card.name}" ليبثه الموبايل للقارئ بالتلامس!')),
                                    );
                                  } else if (value == 'wipe_tag') {
                                    _confirmAndWipePhysicalTag(card: card);
                                  } else if (value == 'delete') {
                                    _confirmDeleteFromVault(card);
                                  }
                                },
                                itemBuilder: (ctx) => [
                                  PopupMenuItem(
                                    value: 'star',
                                    child: Row(children: [
                                      Icon(card.isStarred ? Icons.star_outline : Icons.star, size: 18, color: Colors.amber),
                                      const SizedBox(width: 8),
                                      Text(card.isStarred ? 'إزالة من خانة المهم' : 'إضافة إلى خانة المهم ⭐'),
                                    ]),
                                  ),
                                  const PopupMenuItem(value: 'edit', child: Row(children: [Icon(Icons.edit, size: 18, color: Colors.blueAccent), SizedBox(width: 8), Text('تعديل كامل لمعلومات البطاقة')])),
                                  const PopupMenuItem(value: 'write', child: Row(children: [Icon(Icons.edit_note, size: 18, color: Color(0xFF10B981)), SizedBox(width: 8), Text('كتابة وتعديل على الشريحة / ملصق')])),
                                  const PopupMenuItem(value: 'probe', child: Row(children: [Icon(Icons.bolt, size: 18, color: Colors.amber), SizedBox(width: 8), Text('فحص هل تقبل الكتابة والتعديل')])),
                                  const PopupMenuItem(value: 'set_active', child: Row(children: [Icon(Icons.sensors, size: 18, color: Colors.green), SizedBox(width: 8), Text('عكس وبث هذا الكارت للقارئ')])),
                                  const PopupMenuItem(value: 'wipe_tag', child: Row(children: [Icon(Icons.delete_forever, size: 18, color: Colors.red), SizedBox(width: 8), Text('مسح وفرمتة البطاقة تماماً ⚠️', style: TextStyle(color: Colors.redAccent))])),
                                  const PopupMenuItem(value: 'delete', child: Row(children: [Icon(Icons.delete_outline, size: 18, color: Colors.grey), SizedBox(width: 8), Text('حذف من المحفظة')])),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ودجت تصميم زر الفلترة مع تمييز خانة المهم بلون ذهبي
  Widget _buildFilterChip(String label, String count, {bool isStarredTab = false}) {
    final isSelected = _selectedFilter == label;
    return ChoiceChip(
      label: Text('$label ($count)'),
      selected: isSelected,
      selectedColor: isStarredTab ? const Color(0xFFD97706) : const Color(0xFF0284C7),
      backgroundColor: const Color(0xFF17223B),
      labelStyle: TextStyle(
        color: isSelected ? Colors.white : (isStarredTab ? Colors.amber : Colors.grey.shade300),
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        fontSize: 12,
      ),
      side: BorderSide(
        color: isStarredTab ? Colors.amber.withOpacity(0.6) : (isSelected ? const Color(0xFF38BDF8) : Colors.white12),
      ),
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedFilter = label);
        }
      },
    );
  }
}

