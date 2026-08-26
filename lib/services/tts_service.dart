import 'dart:io';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter_tts/flutter_tts.dart';

enum TtsState { stopped, playing, paused, loading }

class TtsService {
  static final FlutterTts _tts = FlutterTts();
  static TtsState _state = TtsState.stopped;
  static List<Map<String, String>> _voices = [];
  static Map<String, String>? _selectedVoice;
  static bool _isInitialized = false;

  static double _currentRate = 0.5;
  static double _currentPitch = 1.0;

  static TtsState get state => _state;
  static List<Map<String, String>> get voices => _voices;
  static Map<String, String>? get selectedVoice => _selectedVoice;

  static Future<void> initTts() async {
    if (_isInitialized) return;

    try {
      // Ensure completion before calling next methods
      await _tts.awaitSpeakCompletion(true);

      // Default language setup
      await _tts.setLanguage('en-US');
      await _tts.setSpeechRate(_currentRate);
      await _tts.setPitch(_currentPitch);
      await _tts.setVolume(1.0);

      if (!kIsWeb) {
        if (Platform.isAndroid) {
          // Fix for Android engine speed scaling
          await _tts.setEngine('com.google.android.tts');
        }

        final dynamic rawVoices = await _tts.getVoices;
        if (rawVoices != null && rawVoices is List) {
          _voices = rawVoices.map<Map<String, String>>((v) {
            return {
              'name': v['name']?.toString() ?? 'Default',
              'locale': v['locale']?.toString() ?? 'en-US',
            };
          }).toList();

          final englishVoices = _voices
              .where((v) => (v['locale'] ?? '').startsWith('en'))
              .toList();

          if (englishVoices.isNotEmpty) {
            _selectedVoice = englishVoices.first;
          } else if (_voices.isNotEmpty) {
            _selectedVoice = _voices.first;
          }

          if (_selectedVoice != null) {
            await setVoice(_selectedVoice!);
          }
        }
      } else {
        _voices = [
          {'name': 'Default (Web)', 'locale': 'en-US'},
        ];
        _selectedVoice = _voices.first;
      }

      // Engine Callbacks
      _tts.setStartHandler(() {
        _state = TtsState.playing;
      });

      _tts.setCompletionHandler(() {
        _state = TtsState.stopped;
      });

      _tts.setPauseHandler(() {
        _state = TtsState.paused;
      });

      _tts.setCancelHandler(() {
        _state = TtsState.stopped;
      });

      _tts.setErrorHandler((msg) {
        _state = TtsState.stopped;
        debugPrint('TTS Engine Error: $msg');
      });

      _isInitialized = true;
    } catch (e) {
      debugPrint('Error initializing TTS: $e');
    }
  }

  static Future<void> setVoice(Map<String, String> voice) async {
    _selectedVoice = voice;
    if (voice.containsKey('name') && voice.containsKey('locale')) {
      await _tts.setVoice({"name": voice['name']!, "locale": voice['locale']!});
    }
  }

  static Future<void> setRate(double rate) async {
    _currentRate = rate;
    await _tts.setSpeechRate(rate);
  }

  static Future<void> setPitch(double pitch) async {
    _currentPitch = pitch;
    await _tts.setPitch(pitch);
  }

  static double getRate() => _currentRate;
  static double getPitch() => _currentPitch;

  static Future<void> speak(String text, {double? rate, double? pitch}) async {
    final cleanText = text.trim();
    if (cleanText.isEmpty) return;

    if (!_isInitialized) {
      await initTts();
    }

    await stop();

    _state = TtsState.loading;

    try {
      if (rate != null) {
        _currentRate = rate;
        await _tts.setSpeechRate(rate);
      }
      if (pitch != null) {
        _currentPitch = pitch;
        await _tts.setPitch(pitch);
      }

      _state = TtsState.playing;
      await _tts.speak(cleanText);
    } catch (e) {
      _state = TtsState.stopped;
      debugPrint('TTS speak error: $e');
    }
  }

  static Future<void> pause() async {
    await _tts.pause();
    _state = TtsState.paused;
  }

  static Future<void> stop() async {
    await _tts.stop();
    _state = TtsState.stopped;
  }
}