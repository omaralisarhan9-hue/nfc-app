package com.example.nfc_card_manager;

import android.content.Context;
import android.content.SharedPreferences;
import android.nfc.cardemulation.HostApduService;
import android.os.Bundle;
import android.util.Log;
import java.nio.charset.StandardCharsets;
import java.util.Arrays;

/**
 * خدمة محاكاة البطاقة المضيفة (Host Card Emulation - HCE)
 * وظيفتها: بث وعكس بيانات ومعرف البطاقة المختارة من الموبايل إلى قارئ الباب الذكي / قارئ ID
 */
public class MyNfcHostApduService extends HostApduService {

    private static final String TAG = "NfcHceService";
    
    // Application Identifier (AID) المخصص لمحاكاة بطاقات الوصول الذكية
    // F0010203040506
    private static final byte[] APDU_SELECT_AID = new byte[] {
        (byte) 0x00, // CLA
        (byte) 0xA4, // INS (SELECT FILE / AID)
        (byte) 0x04, // P1 (Select by name / AID)
        (byte) 0x00, // P2
        (byte) 0x07, // Lc (Length = 7 bytes)
        (byte) 0xF0, (byte) 0x01, (byte) 0x02, (byte) 0x03, (byte) 0x04, (byte) 0x05, (byte) 0x06 // AID
    };

    // أكواد الاستجابة القياسية لبروتوكول ISO-7816-4
    private static final byte[] STATUS_SUCCESS = new byte[] { (byte) 0x90, (byte) 0x00 };
    private static final byte[] STATUS_FAILED = new byte[] { (byte) 0x6F, (byte) 0x00 };

    @Override
    public byte[] processCommandApdu(byte[] commandApdu, Bundle extras) {
        if (commandApdu == null) {
            return STATUS_FAILED;
        }

        Log.d(TAG, "تلقى الهاتف أمر APDU من قارئ الـ ID خارجي!");

        // جلب المفتاح النشط المخزن في التطبيق
        SharedPreferences prefs = getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE);
        String activeCardJson = prefs.getString("flutter.active_emulation_card", null);

        String payloadToSend = "NFC_KEY_DEFAULT";
        if (activeCardJson != null && !activeCardJson.isEmpty()) {
            payloadToSend = activeCardJson;
        }

        byte[] payloadBytes = payloadToSend.getBytes(StandardCharsets.UTF_8);
        byte[] response = new byte[payloadBytes.length + STATUS_SUCCESS.length];
        System.arraycopy(payloadBytes, 0, response, 0, payloadBytes.length);
        System.arraycopy(STATUS_SUCCESS, 0, response, payloadBytes.length, STATUS_SUCCESS.length);

        Log.d(TAG, "تم بنجاح بث وعكس بيانات البطاقة للقارئ: " + payloadToSend);
        return response;
    }

    @Override
    public void onDeactivated(int reason) {
        Log.d(TAG, "انتهى اتصال التلامس مع القارئ. السبب: " + reason);
    }
}
