// check-conflicts.js — verifica que cada ON CONFLICT (cols) tenga un índice
// único que lo respalde. Detecta el error 42P10 ("there is no unique or
// exclusion constraint matching the ON CONFLICT specification") ANTES de
// cargar el SQL, que es como se manifestó en 0015_seed.sql:
//   indice: create unique index ... on public.draw_sources (lower(code))
//   uso:    insert into public.draw_sources ... on conflict (code)
//
// Uso: node scripts/check-conflicts.js supabase/migrations/*.sql

const fs = require('fs');
const path = require('path');
const { splitStatements } = require('./validate-sql.cjs');

// Tablas gestionadas por Supabase: no conocemos sus constraints, se omiten.
const TABLAS_EXTERNAS = new Set(['storage.buckets', 'storage.objects']);

function norm(cols) {
  return cols
    .split(',')
    .map((c) => c.trim().toLowerCase()
      .replace(/^public\./, '')
      .replace(/\s+/g, '')
      .replace(/^\(+|\)+$/g, ''))
    .filter(Boolean)
    .join(',');
}

// Uniques declarados dentro de un CREATE TABLE.
function uniquesDeTabla(body) {
  const keys = [];
  const sinComentarios = body.replace(/--[^\n]*/g, '');

  // constraint nombre unique (cols)   |   unique (cols)
  const reUnique = /(?:constraint\s+\w+\s+)?unique\s*\(([^)]*)\)/gi;
  let m;
  while ((m = reUnique.exec(sinComentarios)) !== null) keys.push({ key: norm(m[1]), origen: 'unique' });

  // primary key (cols)
  const rePk = /primary\s+key\s*\(([^)]*)\)/gi;
  while ((m = rePk.exec(sinComentarios)) !== null) keys.push({ key: norm(m[1]), origen: 'primary key' });

  // columnas con primary key / unique inline
  const lineas = sinComentarios.split('\n');
  for (const ln of lineas) {
    const t = ln.trim().replace(/,$/, '');
    const inlinePk = /^([a-z_][a-z0-9_]*)\s+[^,]*\bprimary\s+key\b/i.exec(t);
    if (inlinePk) keys.push({ key: inlinePk[1].toLowerCase(), origen: 'primary key inline' });
    const inlineUq = /^([a-z_][a-z0-9_]*)\s+[^,]*\bunique\b/i.exec(t);
    if (inlineUq) keys.push({ key: inlineUq[1].toLowerCase(), origen: 'unique inline' });
  }
  return keys;
}

function main() {
  const files = process.argv.slice(2);
  const tablas = new Map();   // tabla -> [{key, origen}]
  const inserts = [];         // {tabla, target, file, line}

  const addKey = (tabla, key, origen) => {
    if (!tablas.has(tabla)) tablas.set(tabla, []);
    const arr = tablas.get(tabla);
    if (!arr.some((k) => k.key === key)) arr.push({ key, origen });
  };

  for (const file of files) {
    const stmts = splitStatements(fs.readFileSync(file, 'utf8'));
    for (const st of stmts) {
      const sql = st.sql;

      // CREATE TABLE
      const ct = /create\s+table\s+(?:if\s+not\s+exists\s+)?(public\.\w+)\s*\(/i.exec(sql);
      if (ct) {
        const tabla = ct[1].toLowerCase();
        const body = sql.slice(ct.index + ct[0].length);
        for (const k of uniquesDeTabla(body)) addKey(tabla, k.key, k.origen);
      }

      // CREATE UNIQUE INDEX ... ON tabla (expr)
      const ci = /create\s+unique\s+index\s+(?:if\s+not\s+exists\s+)?\w+\s+on\s+(public\.\w+)\s*\(([^)]*)\)/gi;
      let m;
      while ((m = ci.exec(sql)) !== null) {
        addKey(m[1].toLowerCase(), norm(m[2]), 'unique index');
      }

      // INSERT INTO tabla ... ON CONFLICT (cols)
      const ins = /insert\s+into\s+(public\.\w+)/i.exec(sql);
      if (ins) {
        const oc = /on\s+conflict\s*\(([^)]*)\)/i.exec(sql);
        if (oc) {
          inserts.push({
            tabla: ins[1].toLowerCase(),
            target: norm(oc[1]),
            crudo: oc[1].trim(),
            file: path.basename(file),
            line: st.line,
          });
        }
      }
    }
  }

  let errores = 0;
  for (const it of inserts) {
    if (TABLAS_EXTERNAS.has(it.tabla)) continue;
    const keys = tablas.get(it.tabla) || [];
    const ok = keys.some((k) => k.key === it.target);
    if (!ok) {
      errores++;
      console.log(`${it.file}:${it.line}  ON CONFLICT (${it.crudo}) en ${it.tabla}`);
      console.log(`    uniques disponibles: ${keys.length ? keys.map((k) => `${k.key} [${k.origen}]`).join(' | ') : 'NINGUNO'}`);
    }
  }

  if (errores === 0) {
    console.log(`OK: ${inserts.length} ON CONFLICT verificados, todos con indice unico que los respalda.`);
  } else {
    console.log(`\n${errores} ON CONFLICT sin indice unico -> fallaria con 42P10.`);
    process.exit(1);
  }
}

main();