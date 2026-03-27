"use strict";

/**
 * Minimal Lua table parser — handles the subset used by SavedVariables:
 * strings, numbers, booleans, nil, nested tables (both array and hash style).
 */
function parseLuaTable(input) {
  let pos = 0;
  const src = input;

  function skipWhitespace() {
    while (pos < src.length && /[\s]/.test(src[pos])) pos++;
    if (src[pos] === "-" && src[pos + 1] === "-") {
      while (pos < src.length && src[pos] !== "\n") pos++;
      skipWhitespace();
    }
  }

  function parseValue() {
    skipWhitespace();
    if (src[pos] === "{") return parseTable();
    if (src[pos] === '"' || src[pos] === "'") return parseString();
    if (src.startsWith("true", pos)) { pos += 4; return true; }
    if (src.startsWith("false", pos)) { pos += 5; return false; }
    if (src.startsWith("nil", pos)) { pos += 3; return null; }
    return parseNumber();
  }

  function parseString() {
    const quote = src[pos++];
    let str = "";
    while (pos < src.length && src[pos] !== quote) {
      if (src[pos] === "\\") {
        pos++;
        if (src[pos] === "n") str += "\n";
        else if (src[pos] === "t") str += "\t";
        else if (src[pos] === "\\") str += "\\";
        else if (src[pos] === quote) str += quote;
        else str += src[pos];
      } else {
        str += src[pos];
      }
      pos++;
    }
    pos++;
    return str;
  }

  function parseNumber() {
    const start = pos;
    if (src[pos] === "-") pos++;
    while (pos < src.length && /[0-9.]/.test(src[pos])) pos++;
    return parseFloat(src.slice(start, pos));
  }

  function parseTable() {
    pos++; // skip {
    const obj = {};
    const arr = [];
    let isArray = true;
    let arrayIdx = 1;

    while (true) {
      skipWhitespace();
      if (src[pos] === "}") { pos++; break; }
      if (src[pos] === ",") { pos++; continue; }

      let key = null;
      const saved = pos;

      if (src[pos] === "[") {
        pos++;
        skipWhitespace();
        if (src[pos] === '"' || src[pos] === "'") {
          key = parseString();
        } else {
          key = parseNumber();
        }
        skipWhitespace();
        pos++; // skip ]
        skipWhitespace();
        pos++; // skip =
        isArray = false;
      } else if (/[a-zA-Z_]/.test(src[pos])) {
        const idStart = pos;
        while (pos < src.length && /[a-zA-Z0-9_]/.test(src[pos])) pos++;
        const id = src.slice(idStart, pos);
        skipWhitespace();
        if (src[pos] === "=") {
          key = id;
          pos++;
          isArray = false;
        } else {
          pos = saved;
        }
      }

      const val = parseValue();
      skipWhitespace();
      if (src[pos] === ",") pos++;

      if (key !== null) {
        obj[key] = val;
      } else {
        arr.push(val);
        obj[arrayIdx++] = val;
      }
    }

    return isArray && arr.length > 0 ? arr : obj;
  }

  return parseValue();
}

/**
 * Convert JS object to Lua table string.
 */
function toLuaTable(obj, indent = 0) {
  const pad = "  ".repeat(indent);
  const pad1 = "  ".repeat(indent + 1);

  if (obj === null || obj === undefined) return "nil";
  if (typeof obj === "boolean") return obj ? "true" : "false";
  if (typeof obj === "number") return String(obj);
  if (typeof obj === "string") return `"${obj.replace(/\\/g, "\\\\").replace(/"/g, '\\"').replace(/\n/g, "\\n")}"`;

  if (Array.isArray(obj)) {
    if (obj.length === 0) return "{}";
    const items = obj.map(v => `${pad1}${toLuaTable(v, indent + 1)},`);
    return `{\n${items.join("\n")}\n${pad}}`;
  }

  const keys = Object.keys(obj);
  if (keys.length === 0) return "{}";
  const items = keys.map(k => {
    const val = toLuaTable(obj[k], indent + 1);
    if (/^[a-zA-Z_][a-zA-Z0-9_]*$/.test(k)) {
      return `${pad1}${k} = ${val},`;
    }
    return `${pad1}["${k}"] = ${val},`;
  });
  return `{\n${items.join("\n")}\n${pad}}`;
}

/**
 * Parse a SavedVariables file content.
 */
function parseSavedVariables(content) {
  const vars = {};
  const regex = /^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*/gm;
  let match;
  while ((match = regex.exec(content)) !== null) {
    const varName = match[1];
    const startPos = match.index + match[0].length;
    let pos = startPos;
    const src = content;

    if (src[pos] === "{") {
      let depth = 0;
      let inStr = false;
      let strChar = "";
      for (; pos < src.length; pos++) {
        if (inStr) {
          if (src[pos] === "\\") { pos++; continue; }
          if (src[pos] === strChar) inStr = false;
          continue;
        }
        if (src[pos] === '"' || src[pos] === "'") { inStr = true; strChar = src[pos]; continue; }
        if (src[pos] === "{") depth++;
        if (src[pos] === "}") { depth--; if (depth === 0) { pos++; break; } }
      }
      try {
        const tableStr = src.slice(startPos, pos);
        vars[varName] = parseLuaTable(tableStr);
      } catch { vars[varName] = null; }
    }
  }
  return vars;
}

function toSavedVariable(name, value) {
  return `${name} = ${toLuaTable(value)}\n`;
}

module.exports = { parseLuaTable, toLuaTable, parseSavedVariables, toSavedVariable };
