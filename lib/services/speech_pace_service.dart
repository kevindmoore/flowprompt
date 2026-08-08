import 'dart:async';
import 'dart:math' as math;

import 'package:lumberdash/lumberdash.dart';
import 'package:speech_to_text/speech_recognition_error.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import 'package:flowprompt/signals/prompter_signals.dart';

class SpeechPaceService {
  factory SpeechPaceService() => _instance;

  SpeechPaceService._();

  static final SpeechPaceService _instance = SpeechPaceService._();

  static const _neutralDelay = Duration(milliseconds: 900);
  static const _restartDelay = Duration(milliseconds: 250);
  static const _errorRestartDelay = Duration(milliseconds: 750);
  static const _listenWatchdogInterval = Duration(seconds: 2);
  static const _quietStopDelay = Duration(seconds: 2);
  static const _recentSpeechWindow = Duration(seconds: 2);
  static const _speechTimeoutError = 'error_speech_timeout';
  static const _noMatchError = 'error_no_match';
  static const _maxPhraseWords = 8;
  static const _minimumReacquireWords = 6;
  static const _trackedSearchWordsBehind = 8;
  static const _trackedSearchWordsAhead = 40;
  static const _exactMatchScore = 2;
  static const _nearMatchScore = 1;
  static const _minimumMatchScoreFloor = 4;
  static const _speedSmoothing = 0.6;
  static const _positionSmoothing = 0.85;
  static const _stoppedMultiplier = 0.0;
  static const _slowSpeechMultiplier = 0.45;
  static const _approachingReadingZoneMultiplier = 0.6;
  static const _onPaceMultiplier = 0.75;
  static const _catchUpMultiplier = 1.5;
  static const _farCatchUpMultiplier = 3.0;
  static const _slowZoneEndWords = 24;
  static const _readingZoneStartWords = 36;
  static const _readingZoneEndWords = 52;
  static const _catchUpWords = 68;
  static const _neutralMultiplier = 1.0;
  static const _htmlTagOpenCodeUnit = 60;
  static const _htmlTagCloseCodeUnit = 62;
  static const _zeroCodeUnit = 48;
  static const _nineCodeUnit = 57;
  static const _apostropheCodeUnit = 39;
  static const _lowercaseACodeUnit = 97;
  static const _lowercaseZCodeUnit = 122;

  final SpeechToText _speech = SpeechToText();
  final List<String> _scriptWords = [];
  final List<String> _lastResultWords = [];
  Timer? _restartTimer;
  Timer? _neutralTimer;
  Timer? _quietTimer;
  Timer? _listenWatchdog;
  bool _initialized = false;
  bool _enabled = false;
  bool _paused = false;
  bool _starting = false;
  bool _restarting = false;
  bool _loggedSoundForSession = false;
  bool _loggedResultForSession = false;
  DateTime? _lastSpeechAt;
  int? _lastMatchedWordIndex;
  double _activeSpeechMultiplier = _onPaceMultiplier;
  void Function()? onSpeechActivity;
  void Function(int matchedWordIndex)? onSpeechMatch;

  void updateScript(String content) {
    _scriptWords
      ..clear()
      ..addAll(_tokenize(content));
    _lastMatchedWordIndex = null;
  }

  void adjustForRenderedPosition(double topFraction) {
    if (!_enabled || _paused) {
      return;
    }

    late final double targetMultiplier;
    if (topFraction < 0.3) {
      targetMultiplier = _stoppedMultiplier;
    } else if (topFraction < 0.38) {
      targetMultiplier = _approachingReadingZoneMultiplier;
    } else if (topFraction <= 0.45) {
      targetMultiplier = 0.9;
    } else if (topFraction <= 0.55) {
      targetMultiplier = _catchUpMultiplier;
    } else {
      targetMultiplier = _farCatchUpMultiplier;
    }
    _activeSpeechMultiplier = _activeSpeechMultiplier +
        ((targetMultiplier - _activeSpeechMultiplier) * _positionSmoothing);
    logMessage(
      'SpeechFollow: rendered position top=$topFraction, nextMultiplier=$_activeSpeechMultiplier',
    );
  }

  Future<void> setEnabled(bool enabled, {bool startPaused = false}) async {
    logMessage(
      'SpeechFollow: setEnabled($enabled, startPaused=$startPaused)',
    );
    _enabled = enabled;
    _paused = enabled && startPaused;
    _lastSpeechAt = null;
    _lastMatchedWordIndex = null;
    _activeSpeechMultiplier = _onPaceMultiplier;
    _lastResultWords.clear();
    speechFollowEnabled.value = enabled;

    if (!enabled) {
      _restartTimer?.cancel();
      _neutralTimer?.cancel();
      _quietTimer?.cancel();
      _listenWatchdog?.cancel();
      _setMultiplier(_neutralMultiplier);
      speechListening.value = false;
      speechFollowStatus.value = 'Off';
      await _speech.stop();
      return;
    }

    if (_scriptWords.isEmpty) {
      speechFollowStatus.value = 'No script text';
      speechFollowEnabled.value = false;
      _enabled = false;
      return;
    }

    if (_paused) {
      _restartTimer?.cancel();
      _neutralTimer?.cancel();
      _quietTimer?.cancel();
      _listenWatchdog?.cancel();
      _setMultiplier(_stoppedMultiplier);
      speechListening.value = false;
      speechFollowStatus.value = 'Ready';
      await _speech.stop();
      return;
    }

    _startListenWatchdog();
    await _start();
  }

  Future<void> pause() async {
    if (!_enabled) {
      return;
    }
    _paused = true;
    _activeSpeechMultiplier = _onPaceMultiplier;
    _lastMatchedWordIndex = null;
    logMessage('SpeechFollow: paused');
    _lastResultWords.clear();
    _restartTimer?.cancel();
    _neutralTimer?.cancel();
    _quietTimer?.cancel();
    _listenWatchdog?.cancel();
    _setMultiplier(_stoppedMultiplier);
    speechListening.value = false;
    speechFollowStatus.value = 'Paused';
    await _speech.stop();
  }

  Future<void> resume() async {
    if (!_enabled) {
      return;
    }
    _paused = false;
    logMessage('SpeechFollow: resumed');
    _startListenWatchdog();
    await _start();
  }

  Future<void> dispose() async {
    _enabled = false;
    _paused = false;
    _lastSpeechAt = null;
    _lastMatchedWordIndex = null;
    _activeSpeechMultiplier = _onPaceMultiplier;
    _lastResultWords.clear();
    _restartTimer?.cancel();
    _neutralTimer?.cancel();
    _quietTimer?.cancel();
    _listenWatchdog?.cancel();
    _setMultiplier(_neutralMultiplier);
    speechListening.value = false;
    await _speech.stop();
  }

  Future<void> _start() async {
    if (!_enabled || _paused || _starting || _speech.isListening) {
      return;
    }

    _starting = true;

    try {
      if (!_initialized) {
        logMessage('SpeechFollow: initializing recognizer');
        _initialized = await _speech.initialize(
          onStatus: _onStatus,
          onError: _onError,
          options: [SpeechToText.androidNoBluetooth],
        );
        logMessage('SpeechFollow: initialized=$_initialized');
      }

      if (!_initialized) {
        speechFollowEnabled.value = false;
        speechListening.value = false;
        speechFollowStatus.value = 'Speech unavailable';
        _enabled = false;
        _listenWatchdog?.cancel();
        return;
      }

      speechFollowStatus.value = 'Listening';
      if (!_heardSpeechRecently()) {
        _setMultiplier(_stoppedMultiplier);
      }
      _scheduleQuietStop();
      _loggedSoundForSession = false;
      _loggedResultForSession = false;
      logMessage(
        'SpeechFollow: requesting listen, scriptWords=${_scriptWords.length}',
      );
      await _speech.listen(
        onResult: _onResult,
        onSoundLevelChange: _onSoundLevelChange,
        listenOptions: SpeechListenOptions(
          partialResults: true,
          listenMode: ListenMode.dictation,
          cancelOnError: false,
        ),
      );
      logMessage(
        'SpeechFollow: listen returned, isListening=${_speech.isListening}',
      );
    } catch (error) {
      speechListening.value = false;
      speechFollowStatus.value = 'Speech error';
      logWarning('SpeechFollow: listen failed: $error');
    } finally {
      _starting = false;
    }
  }

  void _startListenWatchdog() {
    _listenWatchdog?.cancel();
    _listenWatchdog = Timer.periodic(_listenWatchdogInterval, (_) {
      if (_enabled && !_paused && !speechListening.value) {
        logMessage('SpeechFollow: watchdog restarting red listener');
        unawaited(_restartListening());
      }
    });
  }

  Future<void> _restartListening() async {
    if (!_enabled || _paused || _starting || _restarting) {
      return;
    }
    _restarting = true;
    try {
      logMessage(
        'SpeechFollow: restarting, pluginListening=${_speech.isListening}',
      );
      if (_speech.isListening) {
        await _speech.cancel();
      }
      await _start();
    } finally {
      _restarting = false;
    }
  }

  void _onStatus(String status) {
    logMessage('SpeechFollow: status=$status');
    speechListening.value = status == SpeechToText.listeningStatus;

    if (!_enabled) {
      return;
    }
    if (_paused) {
      speechListening.value = false;
      return;
    }

    if (status == SpeechToText.listeningStatus) {
      _restartTimer?.cancel();
      speechFollowStatus.value = 'Listening';
      return;
    }

    if (status == SpeechToText.doneStatus ||
        status == SpeechToText.notListeningStatus) {
      speechFollowStatus.value = 'Restarting';
      _restartTimer?.cancel();
      _restartTimer = Timer(
        _restartDelay,
        () => unawaited(_restartListening()),
      );
    }
  }

  void _onError(SpeechRecognitionError error) {
    logMessage(
      'SpeechFollow: recognizer error=${error.errorMsg}, permanent=${error.permanent}',
    );
    speechListening.value = false;

    if (!_enabled) {
      return;
    }
    if (_paused) {
      return;
    }

    if (error.errorMsg == _speechTimeoutError ||
        error.errorMsg == _noMatchError) {
      speechFollowStatus.value = _heardSpeechRecently()
          ? 'Restarting'
          : 'Waiting for speech';
      if (!_heardSpeechRecently()) {
        _setMultiplier(_stoppedMultiplier);
      }
      _restartTimer?.cancel();
      _restartTimer = Timer(
        _errorRestartDelay,
        () => unawaited(_restartListening()),
      );
      return;
    }

    logWarning('Speech recognition error: ${error.errorMsg}');
    speechFollowStatus.value = error.permanent
        ? 'Speech error'
        : 'No speech heard';
    _setMultiplier(_stoppedMultiplier);
    if (!error.permanent) {
      _restartTimer?.cancel();
      _restartTimer = Timer(
        _errorRestartDelay,
        () => unawaited(_restartListening()),
      );
    }
  }

  void _onSoundLevelChange(double _) {
    if (!_enabled || _paused) {
      return;
    }

    if (!_loggedSoundForSession) {
      _loggedSoundForSession = true;
      logMessage('SpeechFollow: receiving microphone levels');
    }
  }

  void _onResult(SpeechRecognitionResult result) {
    if (!_enabled || _paused) {
      return;
    }

    final spokenWords = _tokenize(result.recognizedWords);
    if (!_loggedResultForSession || result.finalResult) {
      _loggedResultForSession = true;
      logMessage(
        'SpeechFollow: result words=${spokenWords.length}, final=${result.finalResult}',
      );
    }
    if (!result.finalResult && spokenWords.isEmpty) {
      _scheduleQuietStop();
    }
    if (result.finalResult) {
      _restartTimer?.cancel();
      _restartTimer = Timer(_restartDelay, () {
        logMessage('SpeechFollow: starting next phrase listener');
        unawaited(_restartListening());
      });
    }
    final resultChanged = _resultChanged(spokenWords);
    if (!resultChanged && !result.finalResult) {
      return;
    }

    if (spokenWords.length < 2) {
      return;
    }

    _rememberResult(spokenWords);
    final prompterIndex = _estimatedPrompterWordIndex();
    final matchedIndex = _matchSpokenWords(
      spokenWords,
      allowReacquire:
          result.finalResult && spokenWords.length >= _minimumReacquireWords,
    );
    if (matchedIndex == null) {
      if (result.finalResult) {
        logMessage(
          'SpeechFollow: no script match at prompterWord=$prompterIndex',
        );
      }
      speechFollowStatus.value = 'No script match';
      _activeSpeechMultiplier = _stoppedMultiplier;
      _setMultiplier(_stoppedMultiplier);
      return;
    }

    _lastSpeechAt = DateTime.now();
    onSpeechActivity?.call();
    _scheduleQuietStop();
    final confirmedIndex = math.max(
      matchedIndex,
      _lastMatchedWordIndex ?? matchedIndex,
    );
    _lastMatchedWordIndex = confirmedIndex;
    final delta = confirmedIndex - prompterIndex;
    final targetMultiplier = _multiplierForDelta(delta);
    _activeSpeechMultiplier = _activeSpeechMultiplier +
        ((targetMultiplier - _activeSpeechMultiplier) * _speedSmoothing);
    logMessage(
      'SpeechFollow: matchedWord=$confirmedIndex, prompterWord=$prompterIndex, delta=$delta, targetMultiplier=$targetMultiplier, nextMultiplier=$_activeSpeechMultiplier',
    );
    onSpeechMatch?.call(confirmedIndex);
    _setMultiplier(_activeSpeechMultiplier);
    speechFollowStatus.value = _statusForDelta(delta);

    _neutralTimer?.cancel();
    _neutralTimer = Timer(_neutralDelay, () {
      if (_enabled) {
        speechFollowStatus.value = 'Listening';
      }
    });
  }

  int _estimatedPrompterWordIndex() {
    if (_scriptWords.isEmpty) {
      return 0;
    }
    final progress = currentPrompterProgress.value.clamp(0.0, 1.0);
    return (progress * (_scriptWords.length - 1)).round();
  }

  int? _matchSpokenWords(
    List<String> spokenWords, {
    required bool allowReacquire,
  }) {
    final phrase = spokenWords.length > _maxPhraseWords
        ? spokenWords.sublist(spokenWords.length - _maxPhraseWords)
        : spokenWords;
    int? matchRange(int start, int end, {bool requireUnique = false}) {
      var bestScore = 0;
      var secondBestScore = 0;
      var bestIndex = -1;
      for (var i = start; i < end; i++) {
        var score = 0;
        for (var j = 0; j < phrase.length && i + j < end; j++) {
          if (_scriptWords[i + j] == phrase[j]) {
            score += _exactMatchScore;
          } else if (j > 0 && _scriptWords[i + j - 1] == phrase[j]) {
            score += _nearMatchScore;
          }
        }
        if (score > bestScore) {
          secondBestScore = bestScore;
          bestScore = score;
          bestIndex = i + phrase.length;
        } else if (score > secondBestScore) {
          secondBestScore = score;
        }
      }
      final minimumScore = math.max(_minimumMatchScoreFloor, phrase.length);
      if (bestScore < minimumScore ||
          (requireUnique && bestScore - secondBestScore < _exactMatchScore)) {
        return null;
      }
      return bestIndex;
    }

    int? uniqueExactMatch() {
      var matchedIndex = -1;
      for (var i = 0; i + phrase.length <= _scriptWords.length; i++) {
        var exact = true;
        for (var j = 0; j < phrase.length; j++) {
          if (_scriptWords[i + j] != phrase[j]) {
            exact = false;
            break;
          }
        }
        if (!exact) {
          continue;
        }
        if (matchedIndex >= 0) {
          return null;
        }
        matchedIndex = i + phrase.length;
      }
      return matchedIndex >= 0 ? matchedIndex : null;
    }

    final previousMatch = _lastMatchedWordIndex;
    if (previousMatch != null) {
      final trackedMatch = matchRange(
        math.max(0, previousMatch - _trackedSearchWordsBehind),
        math.min(
          _scriptWords.length,
          previousMatch + _trackedSearchWordsAhead,
        ),
      );
      if (trackedMatch != null) {
        return trackedMatch;
      }
      final reacquiredMatch = allowReacquire ? uniqueExactMatch() : null;
      if (reacquiredMatch != null && reacquiredMatch >= previousMatch) {
        logMessage(
          'SpeechFollow: reacquired delayed phrase, previousWord=$previousMatch, matchedWord=$reacquiredMatch',
        );
        return reacquiredMatch;
      }
      return null;
    }
    return matchRange(
      0,
      _scriptWords.length,
      requireUnique: true,
    );
  }

  double _multiplierForDelta(int delta) {
    if (delta < _slowZoneEndWords) {
      return _slowSpeechMultiplier;
    }
    if (delta < _readingZoneStartWords) {
      return _approachingReadingZoneMultiplier;
    }
    if (delta < _readingZoneEndWords) {
      return _onPaceMultiplier;
    }
    if (delta < _catchUpWords) {
      return _catchUpMultiplier;
    }
    return _farCatchUpMultiplier;
  }

  String _statusForDelta(int delta) {
    if (delta < _readingZoneStartWords) {
      return 'Slowing down';
    }
    if (delta >= _readingZoneEndWords) {
      return 'Speeding up';
    }
    return 'On pace';
  }

  void _scheduleQuietStop() {
    _quietTimer?.cancel();
    _quietTimer = Timer(_quietStopDelay, () {
      if (!_enabled) {
        return;
      }
      logMessage('SpeechFollow: quiet stop, multiplier=0.0');
      speechFollowStatus.value = 'No speech heard';
      _setMultiplier(_stoppedMultiplier);
    });
  }

  bool _heardSpeechRecently() {
    final lastSpeechAt = _lastSpeechAt;
    if (lastSpeechAt == null) {
      return false;
    }
    return DateTime.now().difference(lastSpeechAt) <= _recentSpeechWindow;
  }

  bool _resultChanged(List<String> words) {
    if (words.length != _lastResultWords.length) {
      return true;
    }
    for (var i = 0; i < words.length; i++) {
      if (words[i] != _lastResultWords[i]) {
        return true;
      }
    }
    return false;
  }

  void _rememberResult(List<String> words) {
    _lastResultWords
      ..clear()
      ..addAll(words);
  }

  void _setMultiplier(double multiplier) {
    speechSpeedMultiplier.value = multiplier;
  }

  List<String> _tokenize(String value) {
    final words = <String>[];
    final buffer = StringBuffer();
    var insideTag = false;

    for (final unit in value.toLowerCase().codeUnits) {
      if (unit == _htmlTagOpenCodeUnit) {
        insideTag = true;
        _flushWord(buffer, words);
        continue;
      }
      if (unit == _htmlTagCloseCodeUnit) {
        insideTag = false;
        continue;
      }
      if (insideTag) {
        continue;
      }

      final isLetter =
          unit >= _lowercaseACodeUnit && unit <= _lowercaseZCodeUnit;
      final isDigit = unit >= _zeroCodeUnit && unit <= _nineCodeUnit;
      final isApostrophe = unit == _apostropheCodeUnit;
      if (isLetter || isDigit || isApostrophe) {
        buffer.writeCharCode(unit);
      } else {
        _flushWord(buffer, words);
      }
    }

    _flushWord(buffer, words);
    return words;
  }

  void _flushWord(StringBuffer buffer, List<String> words) {
    if (buffer.isEmpty) {
      return;
    }
    words.add(buffer.toString());
    buffer.clear();
  }
}
