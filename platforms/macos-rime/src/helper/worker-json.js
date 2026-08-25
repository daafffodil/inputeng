ObjC.import("Foundation");

function readText(path) {
  const value = $.NSString.stringWithContentsOfFileEncodingError(
    $(path), $.NSUTF8StringEncoding, null
  );
  return value ? ObjC.unwrap(value) : "";
}

function writeText(path, text) {
  const parent = ObjC.unwrap($(path).stringByDeletingLastPathComponent);
  $.NSFileManager.defaultManager.createDirectoryAtPathWithIntermediateDirectoriesAttributesError(
    $(parent), true, $(), null
  );
  const ok = $(text).writeToFileAtomicallyEncodingError(
    $(path), true, $.NSUTF8StringEncoding, null
  );
  if (!ok) throw new Error("Could not write " + path);
}

function loadTsv(path) {
  const result = {};
  readText(path).split(/\r?\n/).forEach(function (line) {
    if (!line || line.charAt(0) === "#") return;
    const tab = line.indexOf("\t");
    if (tab <= 0) return;
    const key = line.slice(0, tab);
    if (result[key] === undefined) result[key] = line.slice(tab + 1);
  });
  return result;
}

function appendLines(path, lines) {
  if (!lines.length) return;
  const existing = readText(path);
  const prefix = existing && !/\n$/.test(existing) ? existing + "\n" : existing;
  writeText(path, prefix + lines.join("\n") + "\n");
}

function codePoints(text) {
  const values = [];
  for (let index = 0; index < text.length; index += 1) {
    const first = text.charCodeAt(index);
    if (first >= 0xd800 && first <= 0xdbff && index + 1 < text.length) {
      const second = text.charCodeAt(index + 1);
      if (second >= 0xdc00 && second <= 0xdfff) {
        values.push(0x10000 + ((first - 0xd800) << 10) + (second - 0xdc00));
        index += 1;
        continue;
      }
    }
    values.push(first);
  }
  return values;
}

function isHanTerm(text) {
  const points = codePoints(text);
  if (!points.length || points.length > 8) return false;
  return points.every(function (cp) {
    return (cp >= 0x3400 && cp <= 0x4dbf) ||
      (cp >= 0x4e00 && cp <= 0x9fff) ||
      (cp >= 0xf900 && cp <= 0xfaff) ||
      (cp >= 0x20000 && cp <= 0x2ceaf) || cp === 0x3007;
  });
}

function isEnglishTerm(text) {
  return text.length <= 30 && /^[a-z][a-z'-]*$/.test(text);
}

function shortEnglish(value) {
  let text = String(value || "").replace(/\s+/g, " ").trim();
  text = text.replace(/\s*\([^)]*\)/g, "").trim().split(";")[0].trim();
  if (text.length > 24 && text.indexOf(",") >= 0) text = text.split(",")[0].trim();
  if (text.length > 24) {
    const prefix = text.slice(0, 24);
    const boundary = prefix.lastIndexOf(" ");
    text = boundary >= 8 ? prefix.slice(0, boundary) : prefix;
  }
  text = text.replace(/[\s,;:.-]+$/g, "");
  return /[A-Za-z]/.test(text) && !/[\u3400-\u9fff]/.test(text) ? text : "";
}

function shortChinese(value) {
  let text = String(value || "").replace(/\s+/g, "").trim();
  text = text.split(/[；;,，]/)[0].slice(0, 6);
  return /[\u3400-\u9fff]/.test(text) && !/[A-Za-z\t\r\n]/.test(text) ? text : "";
}

function prepare(argv) {
  const direction = argv[1];
  const workPath = argv[2];
  const cachePath = argv[3];
  const offlinePath = argv[4];
  const model = argv[5];
  const bodyPath = argv[6];
  const termsPath = argv[7];
  const queuePath = argv[8];
  const cache = loadTsv(cachePath);
  const offline = direction === "zh-en" ? loadTsv(offlinePath) : {};
  const seen = {};
  const pending = [];
  readText(workPath).split(/\r?\n/).forEach(function (raw) {
    const term = direction === "en-zh" ? raw.trim().toLowerCase() : raw.trim();
    const valid = direction === "zh-en" ? isHanTerm(term) : isEnglishTerm(term);
    if (!valid || seen[term] || cache[term] !== undefined || offline[term] !== undefined) return;
    seen[term] = true;
    pending.push(term);
  });
  const batch = pending.slice(0, 12);
  appendLines(queuePath, pending.slice(12));
  writeText(termsPath, JSON.stringify(batch));
  if (!batch.length) {
    writeText(bodyPath, "");
    return "0";
  }
  const chineseToEnglish = direction === "zh-en";
  const system = chineseToEnglish
    ? "You compile concise English glosses for a Simplified Chinese input method. Return JSON only as {\"translations\":[{\"source\":\"中文\",\"english\":\"short gloss\"}]}. Return one common meaning for every source, using 1 to 4 English words and at most 24 ASCII characters. Preserve every source exactly."
    : "You compile concise Simplified Chinese glosses for English words in an input method. Return JSON only as {\"translations\":[{\"source\":\"english\",\"chinese\":\"简短释义\"}]}. Return one common everyday meaning for every source, using 1 to 6 Chinese characters. Preserve every lowercase source exactly.";
  const body = {
    model: model,
    messages: [
      { role: "system", content: system },
      { role: "user", content: JSON.stringify({ terms: batch }) }
    ],
    thinking: { type: "disabled" },
    response_format: { type: "json_object" },
    temperature: 0.1,
    max_tokens: 512,
    stream: false
  };
  writeText(bodyPath, JSON.stringify(body));
  return String(batch.length);
}

function applyResponse(argv) {
  const direction = argv[1];
  const responsePath = argv[2];
  const termsPath = argv[3];
  const cachePath = argv[4];
  const versionPath = argv[5];
  const requestedArray = JSON.parse(readText(termsPath) || "[]");
  const requested = {};
  requestedArray.forEach(function (term) { requested[term] = true; });
  const response = JSON.parse(readText(responsePath));
  let content = String(response.choices[0].message.content || "").trim();
  content = content.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/, "");
  const root = JSON.parse(content);
  const cache = loadTsv(cachePath);
  let added = 0;
  (root.translations || []).forEach(function (item) {
    const source = direction === "en-zh"
      ? String(item.source || "").toLowerCase() : String(item.source || "");
    const gloss = direction === "zh-en" ? shortEnglish(item.english) : shortChinese(item.chinese);
    if (requested[source] && gloss) {
      cache[source] = gloss;
      added += 1;
    }
  });
  const header = direction === "zh-en"
    ? "# Simplified Chinese | short English gloss; generated locally through the user configured API."
    : "# English word | short Simplified Chinese gloss; generated locally through the user configured API.";
  const lines = [header];
  Object.keys(cache).sort().forEach(function (key) { lines.push(key + "\t" + cache[key]); });
  writeText(cachePath, lines.join("\n") + "\n");
  writeText(versionPath, String(Date.now()) + "\n");
  return String(added);
}

function run(argv) {
  if (!argv.length || argv[0] === "--self-test") {
    if (!isHanTerm("输入法") || isHanTerm("input") || !isEnglishTerm("translate") ||
        shortEnglish("to translate; translation") !== "to translate" ||
        shortChinese("翻译；译文") !== "翻译") {
      throw new Error("worker-json self-test failed");
    }
    return "worker-json self-test passed";
  }
  if (argv[0] === "prepare") return prepare(argv);
  if (argv[0] === "apply") return applyResponse(argv);
  if (argv[0] === "requeue") {
    appendLines(argv[2], JSON.parse(readText(argv[1]) || "[]"));
    return "requeued";
  }
  throw new Error("Unknown mode: " + argv[0]);
}

