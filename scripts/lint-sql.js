// lint-sql.js — verifica que ninguna sentencia SQL quede sin terminar.
// Detecta exactamente la clase de defecto que rompió 0002_tenancy.sql:
// una sentencia (create trigger, create table, ...) a la que le falta el ";"
// y que hace que Postgres reporte el error en la sentencia SIGUIENTE.
//
// Uso: node lint-sql.js <archivos...>

const fs = require('fs');

// Palabras con las que puede empezar una sentencia de nivel superior.
const STMT_START = /^\s*(create|drop|alter|grant|revoke|comment|do|select|insert|update|delete|with|truncate|begin|commit|declare|values|set|lock|analyze|refresh|call|notify|listen|unlisten)\b/i;

// Palabras que, al inicio de linea, son CLARAMENTE una sentencia nueva
// (no una continuacion valida de nada).
const HARD_START = /^\s*(create|drop|alter|grant|revoke|comment\s+on|do\s*\$|insert\s+into|delete\s+from|truncate|begin\b)/i;

function lint(text, filename) {
  const issues = [];
  const lines = text.split('\n');

  let dollarTag = null;   // tag del dollar-quote abierto ($$, $job$, ...)
  let inString = false;   // literal '...' que puede cruzar lineas
  let parens = 0;         // profundidad de parentesis fuera de strings
  let seenSemi = true;    // la sentencia anterior ya cerro
  let stmtStartLine = 0;
  let stmtStartText = '';
  let lastMeaningfulEnd = 0; // ultima linea con contenido de la sentencia abierta

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    const lineNo = i + 1;

    // Si la sentencia esta abierta y aparece una sentencia nueva dura, es error.
    if (!seenSemi && !dollarTag && !inString && parens === 0 && HARD_START.test(raw)) {
      issues.push({
        file: filename,
        line: lineNo,
        openedAt: stmtStartLine,
        openedWith: stmtStartText.trim().slice(0, 70),
        found: raw.trim().slice(0, 70),
      });
      // Reabrimos: tratamos esta linea como el comienzo de una nueva sentencia.
      seenSemi = true;
      stmtStartLine = lineNo;
      stmtStartText = raw;
      lastMeaningfulEnd = lineNo;
    }

    // Escaneo caracter a caracter de la linea, saltando comentarios.
    let j = 0;
    let lineHasContent = false;
    while (j < raw.length) {
      // Comentario de linea: fuera de string y de dollar-quote.
      if (!inString && !dollarTag && raw.startsWith('--', j)) break;

      const ch = raw[j];

      if (dollarTag) {
        if (raw.startsWith(dollarTag, j)) {
          j += dollarTag.length;
          dollarTag = null;
          continue;
        }
        j++;
        continue;
      }

      if (inString) {
        if (ch === "'") {
          if (raw[j + 1] === "'") { j += 2; continue; }  // '' escapado
          inString = false;
        }
        j++;
        continue;
      }

      // Fuera de string y de dollar-quote.
      if (raw.startsWith('--', j)) break;

      if (ch === "'") {
        inString = true;
        lineHasContent = true;
        j++;
        continue;
      }

      // Dollar-quote: $$ o $tag$
      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(raw.slice(j));
      if (m) {
        dollarTag = m[0];
        lineHasContent = true;
        j += m[0].length;
        continue;
      }

      if (ch === '(') { parens++; lineHasContent = true; j++; continue; }
      if (ch === ')') { parens--; lineHasContent = true; j++; continue; }

      if (ch === ';' && parens === 0) {
        seenSemi = true;
        j++;
        continue;
      }

      if (!/\s/.test(ch)) {
        lineHasContent = true;
        if (seenSemi) {
          seenSemi = false;
          stmtStartLine = lineNo;
          stmtStartText = raw;
        }
      }
      j++;
    }

    if (lineHasContent) lastMeaningfulEnd = lineNo;
  }

  // Sentencia abierta al llegar a EOF.
  if (!seenSemi && !dollarTag && !inString) {
    issues.push({
      file: filename,
      line: lines.length,
      openedAt: stmtStartLine,
      openedWith: stmtStartText.trim().slice(0, 70),
      found: '<fin de archivo>',
    });
  }

  if (dollarTag) {
    issues.push({ file: filename, line: lines.length, openedAt: stmtStartLine,
                  openedWith: 'dollar-quote sin cerrar', found: dollarTag });
  }
  if (inString) {
    issues.push({ file: filename, line: lines.length, openedAt: stmtStartLine,
                  openedWith: 'string sin cerrar', found: "'" });
  }

  // Chequeo extra, especifico del defecto real: trigger sin su FOR EACH ROW.
  for (let i = 0; i < lines.length; i++) {
    if (/^create trigger\b/i.test(lines[i].trim())) {
      let found = false;
      for (let k = i + 1; k < Math.min(i + 12, lines.length); k++) {
        if (/for each row|for each statement/i.test(lines[k])) { found = true; break; }
        if (/;\s*$/.test(lines[k]) && /execute function/i.test(lines[k])) { found = true; break; }
        if (/^\s*(create|drop|alter|comment)\b/i.test(lines[k])) break;
      }
      if (!found) {
        issues.push({ file: filename, line: i + 1,
                      openedAt: i + 1,
                      openedWith: 'CREATE TRIGGER sin FOR EACH ROW',
                      found: lines[i].trim().slice(0, 70) });
      }
    }
  }

  return issues;
}

let total = 0;
for (const f of process.argv.slice(2)) {
  const issues = lint(fs.readFileSync(f, 'utf8'), f);
  for (const it of issues) {
    total++;
    console.log(`${it.file}:${it.line}  ${it.openedWith}  ->  ${it.found}`);
  }
}

if (total === 0) {
  console.log('OK: no se detectaron sentencias sin terminar.');
} else {
  console.log(`\n${total} problema(s) detectado(s).`);
  process.exit(1);
}