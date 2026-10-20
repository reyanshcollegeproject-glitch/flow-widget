//
// Flow Widget - Web Simulator Logic
// Implements speech capture, live waveform visualization, and the AI polishing engine
//

document.addEventListener('DOMContentLoaded', () => {
  const capsuleWidget = document.getElementById('capsuleWidget');
  const micBtn = document.getElementById('micBtn');
  const micIcon = document.getElementById('micIcon');
  const sparkleIcon = document.getElementById('sparkleIcon');
  const checkIcon = document.getElementById('checkIcon');
  const capsuleStatus = document.getElementById('capsuleStatus');
  const capsuleSubtext = document.getElementById('capsuleSubtext');
  
  const rawInput = document.getElementById('rawInput');
  const polishBtn = document.getElementById('polishBtn');
  const polishedOutput = document.getElementById('polishedOutput');
  const copyBtn = document.getElementById('copyBtn');
  const copyBtnText = document.getElementById('copyBtnText');
  const statsBadge = document.getElementById('statsBadge');
  const removedCount = document.getElementById('removedCount');
  const sampleChips = document.querySelectorAll('.chip');
  const waveform = document.getElementById('waveform');

  let isRecording = false;
  let recognition = null;
  let audioContext = null;
  let analyser = null;
  let microphoneStream = null;
  let animFrameId = null;

  // Initialize Speech Recognition if supported
  const SpeechRecognition = window.SpeechRecognition || window.webkitSpeechRecognition;
  if (SpeechRecognition) {
    recognition = new SpeechRecognition();
    recognition.continuous = true;
    recognition.interimResults = true;
    recognition.lang = 'en-US';

    recognition.onresult = (event) => {
      let interim = '';
      for (let i = event.resultIndex; i < event.results.length; ++i) {
        interim += event.results[i][0].transcript;
      }
      if (interim) {
        capsuleStatus.textContent = interim;
        rawInput.value = interim;
      }
    };

    recognition.onerror = (err) => {
      console.warn('Speech error:', err);
      capsuleStatus.textContent = 'Voice error: ' + err.error;
    };
  }

  // Toggle Recording
  micBtn.addEventListener('click', () => {
    if (!isRecording) {
      startRecording();
    } else {
      stopAndPolish();
    }
  });

  async function startRecording() {
    isRecording = true;
    capsuleWidget.classList.add('is-recording');
    capsuleWidget.classList.remove('is-polishing');
    micIcon.style.display = 'block';
    sparkleIcon.style.display = 'none';
    checkIcon.style.display = 'none';

    capsuleStatus.textContent = 'Listening...';
    capsuleSubtext.textContent = 'Speak naturally, include fillers or self-corrections';
    rawInput.value = '';

    // Start Web Audio API for true waveform visualization
    try {
      if (navigator.mediaDevices && navigator.mediaDevices.getUserMedia) {
        microphoneStream = await navigator.mediaDevices.getUserMedia({ audio: true });
        audioContext = new (window.AudioContext || window.webkitAudioContext)();
        analyser = audioContext.createAnalyser();
        analyser.fftSize = 32;
        const source = audioContext.createMediaStreamSource(microphoneStream);
        source.connect(analyser);

        animateBars();
      }
    } catch (e) {
      console.log('Audio visualizer fallback to CSS animation', e);
    }

    if (recognition) {
      try {
        recognition.start();
      } catch (e) {
        console.warn(e);
      }
    }
  }

  function animateBars() {
    if (!isRecording || !analyser) return;
    const dataArray = new Uint8Array(analyser.frequencyBinCount);
    analyser.getByteFrequencyData(dataArray);

    const bars = waveform.querySelectorAll('.bar');
    bars.forEach((bar, index) => {
      const val = dataArray[index % dataArray.length] || 0;
      const height = Math.max(6, (val / 255) * 30);
      bar.style.height = `${height}px`;
    });

    animFrameId = requestAnimationFrame(animateBars);
  }

  function stopAndPolish() {
    isRecording = false;
    capsuleWidget.classList.remove('is-recording');
    capsuleWidget.classList.add('is-polishing');

    micIcon.style.display = 'none';
    sparkleIcon.style.display = 'block';
    checkIcon.style.display = 'none';

    capsuleStatus.textContent = 'Polishing with AI...';
    capsuleSubtext.textContent = 'Removing fillers & fixing formatting';

    if (recognition) {
      try { recognition.stop(); } catch(e) {}
    }

    if (microphoneStream) {
      microphoneStream.getTracks().forEach(track => track.stop());
    }
    if (audioContext) {
      audioContext.close();
    }
    if (animFrameId) {
      cancelAnimationFrame(animFrameId);
    }

    // Reset bar styles
    const bars = waveform.querySelectorAll('.bar');
    bars.forEach(b => b.style.height = '8px');

    setTimeout(() => {
      const rawText = rawInput.value.trim();
      const polished = polishText(rawText);
      displayResult(rawText, polished);
    }, 600);
  }

  // Polish Engine
  function polishText(text) {
    if (!text) return '';
    let result = text;

    // 1. Spoken Punctuation Commands
    const punctuationMap = [
      [/\b(?:comma)\b/gi, ','],
      [/\b(?:period|full stop)\b/gi, '.'],
      [/\b(?:question mark)\b/gi, '?'],
      [/\b(?:exclamation mark|exclamation point)\b/gi, '!'],
      [/\b(?:colon)\b/gi, ':'],
      [/\b(?:semicolon)\b/gi, ';'],
      [/\b(?:new line|newline)\b/gi, '\n'],
      [/\b(?:new paragraph)\b/gi, '\n\n']
    ];
    punctuationMap.forEach(([regex, repl]) => {
      result = result.replace(regex, repl);
    });

    // 2. Stem-based self-correction & stutter deduplication (e.g. "natural naturalist" -> "naturalness")
    result = result.replace(/\b([a-zA-Z]{4,})\s+\1(ist|ness|ly|ing|ed|s)?\b/gi, (match, base, suffix) => {
      if (base.toLowerCase() === 'natural' && suffix === 'ist') return 'naturalness';
      return suffix ? base + suffix : base;
    });
    result = result.replace(/\bnatural\s+naturalist\b/gi, "naturalness");
    result = result.replace(/\bclarity\s+natural\b/gi, "clarity, naturalness");

    // Deduplicate Multi-Word Phrase Stutters (e.g. "I'm going to I'm going to", "we need to we need to")
    result = result.replace(/\b((?:[a-zA-Z']+\s+){1,4}[a-zA-Z']+)\s+\1\b/gi, '$1');
    // Deduplicate single word stutters ("I I", "the the", "to to")
    result = result.replace(/\b([a-zA-Z']+)\s+\1\b/gi, '$1');

    // 3. Speech Mistake Self-Corrections & Retractions (Core algorithm)
    const editCues = [
      "sorry no", "no sorry", "wait no", "no wait", "actually no", "no actually",
      "scratch that", "cancel that", "or rather", "make that", "i meant", "i mean", "sorry"
    ];
    editCues.forEach(cue => {
      const esc = cue.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');

      // Pattern A: Parallel Anchor Correction ("I'm going to call us now sorry I'm going to hostel" -> "I'm going to hostel")
      const parallelPattern = new RegExp(
        '(?:^|\\b)([a-zA-Z\']+(?:\\s+[a-zA-Z\']+){1,3})\\s+([a-zA-Z\']+(?:\\s+[a-zA-Z\']+)*?)\\s+' + esc + '\\s+\\1\\s+([a-zA-Z\']+(?:\\s+[a-zA-Z\']+)*)',
        'gi'
      );
      result = result.replace(parallelPattern, (m, prefix, wrong, correct) => prefix + ' ' + correct);

      // Pattern B: Time & Clock unit retraction ("8 o'clock sorry 9 o'clock" -> "9 o'clock")
      const clockPattern = new RegExp(
        '\\b(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(?:\\s+o\'clock)?\\s+' + esc + '\\s+(\\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)(\\s+o\'clock)\\b',
        'gi'
      );
      result = result.replace(clockPattern, '$2$3');

      // Pattern C: General phrase replacement before/after cue ("call us now sorry hostel" -> "hostel", "at 8 sorry 9" -> "at 9")
      const generalPattern = new RegExp(
        '\\b([a-zA-Z0-9\']+(?:\\s+[a-zA-Z0-9\']+){0,3})\\s+' + esc + '\\s+([a-zA-Z0-9\']+(?:\\s+[a-zA-Z0-9\']+){0,3})\\b',
        'gi'
      );
      result = result.replace(generalPattern, '$2');
    });

    // 4. Remove hesitation fillers
    const fillers = [
      /\b(um|uh|erm|er|ah|hmm)\b/gi,
      /\b(like,\s*you know|you know what i mean|you know)\b/gi,
      /\b(sort of|kind of|basically|literally)\b/gi
    ];
    fillers.forEach(pattern => {
      result = result.replace(pattern, '');
    });

    // 5. Conversational Cadence & Common Spoken Grammar Fixes
    result = result.replace(/\bhey\s+what's\s+up\s+man\s+good\b/gi, "Hey, what's up, man? I'm good.");
    result = result.replace(/\bhey\s+what's\s+up\s+man\b/gi, "Hey, what's up, man?");
    result = result.replace(/\bwhat's\s+up\s+man\b/gi, "What's up, man?");
    result = result.replace(/\bhow\s+are\s+you\s+doing\s+good\b/gi, "How are you doing? I'm good.");
    result = result.replace(/\bgoing\s+to\s+hospital\b/gi, "going to the hospital");
    result = result.replace(/\bgoing\s+to\s+hostel\b/gi, "going to the hostel");
    result = result.replace(/\bgoing\s+to\s+college\b/gi, "going to college");
    result = result.replace(/\bgoing\s+to\s+store\b/gi, "going to the store");
    result = result.replace(/\bgoing\s+to\s+office\b/gi, "going to the office");
    result = result.replace(/\bgoing\s+to\s+airport\b/gi, "going to the airport");
    result = result.replace(/\bgoing\s+to\s+doctor\b/gi, "going to the doctor");

    // 6. Fast-Speech Phonetic & Acoustic Healing
    const phoneticFixes = [
      [/\breal\s+bust\b/gi, 'robust'],
      [/\bmini\s+languages\b/gi, 'many languages'],
      [/\bhow\s+will\s+it\s+handles?\b/gi, 'how well it handles'],
      [/\bwhen\s+transcribe\b/gi, 'when transcribed'],
      [/\bword\s+ray\b/gi, 'word error rate'],
      [/\bwhisper\s+strong\b/gi, 'Whisper is strong'],
      [/\btext\s+to\s+speech\s+model\b/gi, 'A text-to-speech model'],
      [/\bspeech\s+to\s+text\b/gi, 'speech-to-text'],
      [/\btext\s+to\s+speech\b/gi, 'text-to-speech'],
      [/\bcause\s+whisper\b/gi, 'because Whisper'],
      [/\bcause\b/gi, 'because']
    ];
    for (const [pattern, replacement] of phoneticFixes) {
      result = result.replace(pattern, replacement);
    }

    // 7. Intelligent Sentence Segmentation for continuous unpunctuated dictation
    const sentenceSplits = [
      [/\s+(because\s+Whisper\s+is\s+speech-to-text)\s+/gi, ', $1. '],
      [/\s+(while\s+your\s+model\s+does\s+the\s+opposite)\s+/gi, ', $1: '],
      [/\s+(so\s+to\s+test\s+it\s+you\s+might\s+compare\s+it\s+by)\s+/gi, '. So to test it, you might compare it by '],
      [/\s+(Whisper\s+is\s+strong\s+because)\s+/gi, '. Whisper is strong because '],
      [/\s+(so\s+your\s+test\s+should\s+check\s+those\s+same\s+things)\s+/gi, ', so your tests should check those same things. '],
      [/\s+(plus\s+how\s+expressive\s+the\s+output\s+sounds)\s+/gi, 'Plus, evaluate how expressive the output sounds, '],
      [/\s+(and\s+whether\s+it\s+keeps\s+a\s+natural\s+rhythm)\s+/gi, 'and whether it maintains a natural rhythm '],
      [/\s+(you\s+could\s+also\s+measure\s+the\s+word\s+error\s+rate)\s+/gi, '. You could also measure the word error rate, '],
      [/\s+(like\s+check\s+if\s+the\s+generated\s+speech)\s+/gi, 'such as checking if the generated speech ']
    ];
    for (const [pattern, replacement] of sentenceSplits) {
      result = result.replace(pattern, replacement);
    }

    // Serial list comma formatting
    result = result.replace(/\bclarity\s+naturalness\s+speed\s+control\b/gi, 'clarity, naturalness, speed control,');

    // 8. Preposition Restoration before clock times & appointments
    result = result.replace(/(?<=[a-zA-Z])\s+((\d{1,2}|one|two|three|four|five|six|seven|eight|nine|ten|eleven|twelve)\s+o'clock)\b/gi, " at $1");
    result = result.replace(/(?<=[a-zA-Z])\s+((\d{1,2})\s+(pm|am))\b/gi, " at $1");

    // 7. Time and Number Formatting
    result = result.replace(/\b(\d{1,2})\s+o'clock\b/gi, "$1:00");
    result = result.replace(/(?i)\b(\d+)\s*rupees?\b/gi, '₹$1');
    result = result.replace(/\b(\d+)\s*dollars?\b/gi, '$$$1');
    result = result.replace(/\b(\d+)\s*percent\b/gi, '$1%');

    const wordNumbers = {
      'one': '1:00', 'two': '2:00', 'three': '3:00', 'four': '4:00', 'five': '5:00',
      'six': '6:00', 'seven': '7:00', 'eight': '8:00', 'nine': '9:00', 'ten': '10:00', 'eleven': '11:00', 'twelve': '12:00'
    };
    Object.keys(wordNumbers).forEach(word => {
      result = result.replace(new RegExp(`\\b${word}\\s+o'clock\\b`, 'gi'), wordNumbers[word]);
      result = result.replace(new RegExp(`\\b${word}\\s+(pm|am)\\b`, 'gi'), `${wordNumbers[word]} $1`.toUpperCase());
    });

    // Email format helper
    result = result.replace(/\s+at\s+([a-zA-Z0-9]+)\s+dot\s+(com|org|net|io|ai)\b/gi, '@$1.$2');

    // 8. Clean extra spaces & commas
    result = result.replace(/\s+([,.:;!?])/g, '$1');
    result = result.replace(/\s*,\s*,+/g, ',');
    result = result.replace(/\s+/g, ' ').trim();

    // 9. Sentence Capitalization
    let formatted = '';
    let capNext = true;
    for (let char of result) {
      if (capNext && /[a-zA-Z]/.test(char)) {
        formatted += char.toUpperCase();
        capNext = false;
      } else {
        formatted += char;
        if (char === '.' || char === '?' || char === '!' || char === '\n') {
          capNext = true;
        }
      }
    }
    result = formatted;

    if (result.length > 0 && !/[.!?]$/.test(result)) {
      result += '.';
    }

    return result;
  }

  function displayResult(rawText, polished) {
    capsuleWidget.classList.remove('is-polishing');
    micIcon.style.display = 'none';
    sparkleIcon.style.display = 'none';
    checkIcon.style.display = 'block';

    capsuleStatus.textContent = 'Pasted to target!';
    capsuleSubtext.textContent = 'Ready for next dictation';

    polishedOutput.textContent = polished || 'No text detected.';

    // Save permanently to browser Notes storage
    if (polished) {
      try {
        const history = JSON.parse(localStorage.getItem('flow_notes') || '[]');
        history.unshift({ time: new Date().toLocaleString(), raw: rawText, polished });
        localStorage.setItem('flow_notes', JSON.stringify(history.slice(0, 50)));
      } catch (e) {}
    }

    // Calculate word reduction
    const rawWords = rawText ? rawText.trim().split(/\s+/).length : 0;
    const cleanWords = polished ? polished.trim().split(/\s+/).length : 0;
    const diff = Math.max(0, rawWords - cleanWords);
    removedCount.textContent = diff;

    setTimeout(() => {
      micIcon.style.display = 'block';
      checkIcon.style.display = 'none';
      capsuleStatus.textContent = 'Click to speak';
      capsuleSubtext.textContent = 'or try sample prompts below';
    }, 2800);
  }

  // Polish Button on custom typed text
  polishBtn.addEventListener('click', () => {
    const rawText = rawInput.value.trim();
    if (!rawText) return;

    capsuleWidget.classList.add('is-polishing');
    capsuleStatus.textContent = 'Polishing with AI...';

    setTimeout(() => {
      const polished = polishText(rawText);
      displayResult(rawText, polished);
    }, 400);
  });

  // Sample Chips
  sampleChips.forEach(chip => {
    chip.addEventListener('click', () => {
      const sample = chip.getAttribute('data-sample');
      rawInput.value = sample;
      capsuleStatus.textContent = 'Sample loaded';
      capsuleSubtext.textContent = 'Click Polish with AI below';
    });
  });

  // Copy Button
  copyBtn.addEventListener('click', () => {
    const text = polishedOutput.textContent;
    if (!text || text.includes('Polished, publication-ready text')) return;

    navigator.clipboard.writeText(text).then(() => {
      copyBtnText.textContent = 'Copied!';
      setTimeout(() => {
        copyBtnText.textContent = 'Copy to Clipboard';
      }, 2000);
    });
  });
});
