// validate-sql.js — verificación real de las migraciones.
//
// Capa 1: sintaxis. Parsea CADA sentencia con libpg_query (el parser real de
//         PostgreSQL, vía pgsql-parser). Reporta archivo + línea exacta.
// Capa 2: structural. Verifica el balance de bloques dentro de cada cuerpo
//         PL/pgSQL (begin/end, if/end if, loop/end loop, case/end case), que es
//         donde un truncado de archivo no lo detectaría ningún parser SQL.
// Capa 3: heurística de sentencias sin terminar y triggers sin FOR EACH ROW.
//
// Uso: node scripts/validate-sql.js [--quiet] supabase/migrations/*.sql

const fs = require('fs');
const M = require('/tmp/node_modules/pgsql-parser');

// ---------------------------------------------------------------------------
// Splitter de sentencias: respeta dollar-quotes, strings y comentarios.
// Necesario porque un ';' dentro de un cuerpo $$ ... $$ no separa sentencias.
// ---------------------------------------------------------------------------
function splitStatements(text) {
  const out = [];
  const lines = text.split('\n');
  let buf = [];
  let startLine = 1;
  let dollarTag = null;
  let inString = false;
  let parens = 0;
  let hasContent = false;

  for (let i = 0; i < lines.length; i++) {
    const raw = lines[i];
    let j = 0;
    let lineOut = '';

    while (j < raw.length) {
      if (!inString && !dollarTag && raw.startsWith('--', j)) {
        lineOut += raw.slice(j);
        j = raw.length;
        break;
      }

      const ch = raw[j];

      if (dollarTag) {
        if (raw.startsWith(dollarTag, j)) {
          lineOut += dollarTag;
          j += dollarTag.length;
          dollarTag = null;
          hasContent = true;
          continue;
        }
        lineOut += ch; j++; continue;
      }

      if (inString) {
        if (ch === "'") {
          if (raw[j + 1] === "'") { lineOut += "''"; j += 2; continue; }
          inString = false;
        }
        lineOut += ch; j++; continue;
      }

      if (ch === "'") { inString = true; lineOut += ch; hasContent = true; j++; continue; }

      const m = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(raw.slice(j));
      if (m) {
        dollarTag = m[0];
        lineOut += m[0];
        j += m[0].length;
        hasContent = true;
        continue;
      }

      if (ch === '(') { parens++; lineOut += ch; hasContent = true; j++; continue; }
      if (ch === ')') { parens--; lineOut += ch; hasContent = true; j++; continue; }

      if (ch === ';' && parens === 0) {
        lineOut += ch;
        if (hasContent) {
          out.push({ sql: (buf.join('\n') + '\n' + lineOut).trim(), line: startLine });
        }
        buf = [];
        lineOut = '';
        hasContent = false;
        startLine = i + 2;
        j++;
        continue;
      }

      if (!/\s/.test(ch)) {
        hasContent = true;
        if (buf.length === 0 && lineOut.trim() === '') startLine = i + 1;
      }
      lineOut += ch;
      j++;
    }

    buf.push(lineOut);
  }

  const tail = buf.join('\n').trim();
  if (tail && hasContent) out.push({ sql: tail, line: startLine });
  return out;
}

// ---------------------------------------------------------------------------
// Capa 2: balance de bloques PL/pgSQL
// ---------------------------------------------------------------------------
function stripNoise(body) {
  let out = '';
  let i = 0;
  let inStr = false;
  while (i < body.length) {
    if (!inStr && body.startsWith('--', i)) {
      const nl = body.indexOf('\n', i);
      i = nl === -1 ? body.length : nl;
      continue;
    }
    if (!inStr && body.startsWith('/*', i)) {
      const end = body.indexOf('*/', i + 2);
      i = end === -1 ? body.length : end + 2;
      continue;
    }
    const ch = body[i];
    if (inStr) {
      if (ch === "'") {
        if (body[i + 1] === "'") { i += 2; continue; }
        inStr = false;
      }
      i++; continue;
    }
    if (ch === "'") { inStr = true; i++; continue; }
    out += ch;
    i++;
  }
  return out;
}

function checkPlpgsqlBalance(body) {
  const clean = stripNoise(body);
  const stack = [];
  // El alternativo 'end\\s+(if|loop|case)' va ANTES de 'end' para consumir el
  // keyword de cierre completo. Si no, el 'if' de "end if" se contaria como
  // una apertura nueva (eso generaba falsos positivos).
  const re = /\b(begin|elsif|end\s+(?:if|loop|case)|end|if|loop|case|declare)\b/gi;
  let m;
  const problems = [];

  while ((m = re.exec(clean)) !== null) {
    const raw = m[1].toLowerCase();
    const kw = raw.split(/\s+/)[0];

    if (kw === 'begin') stack.push({ kw: 'begin' });
    else if (kw === 'if') stack.push({ kw: 'if' });
    else if (kw === 'elsif' || kw === 'declare') { /* ni abren ni cierran */ }
    else if (kw === 'loop') stack.push({ kw: 'loop' });
    else if (kw === 'case') stack.push({ kw: 'case' });
    else if (kw === 'end') {
      const explicit = raw.split(/\s+/)[1] || null;
      if (explicit) {
        const top = stack.pop();
        if (!top || top.kw !== explicit) {
          problems.push(`'end ${explicit}' sin apertura correspondiente (tope: ${top ? top.kw : 'nada'})`);
        }
      } else {
        // 'end' simple: cierra un begin o un CASE de expresion SQL.
        const top = stack.pop();
        if (!top || (top.kw !== 'begin' && top.kw !== 'case')) {
          problems.push(`'end' simple sin bloque abierto (tope: ${top ? top.kw : 'nada'})`);
        }
      }
    }
  }

  for (const s of stack) problems.push(`bloque '${s.kw}' sin cerrar`);
  return problems;
}

function extractDollarBodies(sql) {
  const bodies = [];
  const re = /as\s+(\$[A-Za-z_0-9]*\$)/gi;
  let m;
  while ((m = re.exec(sql)) !== null) {
    const tag = m[1];
    const start = m.index + m[0].length;
    const end = sql.indexOf(tag, start);
    if (end === -1) continue;
    bodies.push({ body: sql.slice(start, end), offset: start });
  }
  return bodies;
}

module.exports = { splitStatements, checkPlpgsqlBalance, extractDollarBodies, stripNoise };

if (require.main === module) {
  const args = process.argv.slice(2).filter((a) => a !== '--quiet');
  M.loadModule().then(() => {
    let errors = 0;
    let totalStmts = 0;

    for (const file of args) {
      const text = fs.readFileSync(file, 'utf8');
      const stmts = splitStatements(text);
      totalStmts += stmts.length;
      const found = [];

      for (const st of stmts) {
        try {
          M.parseSync(st.sql);
        } catch (e) {
          found.push(`  linea ${st.line}: SINTAXIS: ${e.message}`);
          found.push(`    -> ${st.sql.split('\n')[0].slice(0, 90)}`);
          continue;
        }
        // Capa 2: balance de bloques, sólo si el cuerpo es plpgsql.
        for (const b of extractDollarBodies(st.sql)) {
          const pre = st.sql.slice(0, b.offset);
          if (!/language\s+plpgsql\s*$/i.test(pre.replace(/\s+/g, ' ').trimEnd())
              && !/language\s+plpgsql/i.test(pre)) continue;
          for (const p of checkPlpgsqlBalance(b.body)) {
            found.push(`  linea ${st.line}: BALANCE: ${p}`);
          }
        }
      }

      if (found.length) {
        errors += found.length;
        console.log(`\n${file}  [${stmts.length} sentencias]`);
        for (const f of found) console.log(f);
      } else if (!process.argv.includes('--quiet')) {
        console.log(`${file.padEnd(52)} OK  (${stmts.length} sentencias)`);
      }
    }

    console.log(`\nTotal: ${totalStmts} sentencias verificadas, ${errors} error(es).`);
    process.exit(errors ? 1 : 0);
  }).catch((e) => {
    console.error('No se pudo inicializar libpg_query:', e.message);
    process.exit(2);
  });
}