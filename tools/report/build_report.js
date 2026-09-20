/**
 * Builds docs/EndUser_Verification_Report.docx.
 *
 *   cd tools/report && node build_report.js
 *
 * The content lives in report-data.js so the document structure and the
 * findings can be edited independently.
 */
'use strict';

const fs = require('fs');
const path = require('path');
const {
  Document,
  Packer,
  Paragraph,
  TextRun,
  HeadingLevel,
  AlignmentType,
  Table,
  TableRow,
  TableCell,
  WidthType,
  BorderStyle,
  ImageRun,
  PageBreak,
  ShadingType,
} = require('docx');

// `node build_report.js [data-module] [output.docx]` — the structure below is
// the same for both handsets, so the provider report reuses it with its own
// content file rather than being a second copy of this script.
const dataModule = process.argv[2] || './report-data.js';
const outName = process.argv[3] || 'EndUser_Verification_Report.docx';

const data = require(dataModule.startsWith('.')
  ? dataModule
  : './' + dataModule);

const REPO = path.resolve(__dirname, '..', '..');
const SHOTS = path.join(REPO, 'docs', 'screens');
const OUT = path.join(REPO, 'docs', outName);

// --- palette, matching the app's own tokens -------------------------------
const BRAND = '004C8A';
const INK = '1E293B';
const MUTED = '64748B';
const GREEN = '0F7A5A';
const RED = 'B91C1C';
const AMBER = '92400E';
const HEADER_BG = 'E8F0F8';
const ZEBRA_BG = 'F8FAFC';

const NO_BORDER = {
  top: { style: BorderStyle.NONE, size: 0 },
  bottom: { style: BorderStyle.NONE, size: 0 },
  left: { style: BorderStyle.NONE, size: 0 },
  right: { style: BorderStyle.NONE, size: 0 },
};

const HAIRLINE = {
  top: { style: BorderStyle.SINGLE, size: 2, color: 'D7DEE8' },
  bottom: { style: BorderStyle.SINGLE, size: 2, color: 'D7DEE8' },
  left: { style: BorderStyle.SINGLE, size: 2, color: 'D7DEE8' },
  right: { style: BorderStyle.SINGLE, size: 2, color: 'D7DEE8' },
};

function txt(text, opts = {}) {
  return new TextRun({
    text: String(text),
    color: opts.color || INK,
    bold: !!opts.bold,
    italics: !!opts.italics,
    size: opts.size || 20, // half-points: 20 = 10pt
    font: 'Calibri',
  });
}

function p(text, opts = {}) {
  return new Paragraph({
    children: Array.isArray(text) ? text : [txt(text, opts)],
    spacing: { after: opts.after == null ? 120 : opts.after, line: 276 },
    alignment: opts.align,
  });
}

function h1(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_1,
    spacing: { before: 360, after: 180 },
    children: [txt(text, { bold: true, size: 32, color: BRAND })],
  });
}

function h2(text) {
  return new Paragraph({
    heading: HeadingLevel.HEADING_2,
    spacing: { before: 240, after: 120 },
    children: [txt(text, { bold: true, size: 24, color: INK })],
  });
}

function statusColour(s) {
  const v = String(s).toUpperCase();
  if (v.startsWith('PASS') || v.includes('✓')) return GREEN;
  if (v.startsWith('FAIL')) return RED;
  if (v.startsWith('PARTIAL') || v.startsWith('N/A') || v.startsWith('SKIP')) {
    return AMBER;
  }
  return INK;
}

function cell(children, opts = {}) {
  return new TableCell({
    children: Array.isArray(children) ? children : [children],
    width: opts.width
      ? { size: opts.width, type: WidthType.PERCENTAGE }
      : undefined,
    margins: { top: 80, bottom: 80, left: 120, right: 120 },
    shading: opts.shading
      ? { type: ShadingType.CLEAR, fill: opts.shading, color: 'auto' }
      : undefined,
    columnSpan: opts.span,
    verticalAlign: 'center',
  });
}

/** A table with a tinted header row and zebra body rows. */
function table(headers, rows, widths) {
  const headerRow = new TableRow({
    tableHeader: true,
    children: headers.map((htext, i) =>
      cell(p([txt(htext, { bold: true, color: BRAND, size: 19 })], { after: 0 }), {
        width: widths && widths[i],
        shading: HEADER_BG,
      }),
    ),
  });

  const bodyRows = rows.map(
    (r, ri) =>
      new TableRow({
        children: r.map((c, ci) => {
          const isStatus = headers[ci] === 'Status' || headers[ci] === 'Result';
          const body = String(c == null ? '' : c);
          return cell(
            p([
              txt(body, {
                size: 19,
                bold: isStatus,
                color: isStatus ? statusColour(body) : INK,
              }),
            ], { after: 0 }),
            {
              width: widths && widths[ci],
              shading: ri % 2 ? ZEBRA_BG : undefined,
            },
          );
        }),
      }),
  );

  return new Table({
    width: { size: 100, type: WidthType.PERCENTAGE },
    borders: HAIRLINE,
    rows: [headerRow, ...bodyRows],
  });
}

// --- screenshots -----------------------------------------------------------

/** Phone screenshots are 1080x2400; two per row at a readable width. */
const SHOT_W = 200;
const SHOT_H = Math.round((SHOT_W * 2400) / 1080);

function shot(file) {
  const full = path.join(SHOTS, file);
  if (!fs.existsSync(full)) return null;
  return new ImageRun({
    data: fs.readFileSync(full),
    transformation: { width: SHOT_W, height: SHOT_H },
    type: 'png',
  });
}

function missing(count) {
  return p(`(${count} screenshot${count === 1 ? '' : 's'} not captured)`, {
    color: MUTED,
    italics: true,
  });
}

/**
 * One screen: a caption row, then the English and Nepali shots side by side in
 * a borderless two-column table so they stay on the same line.
 */
function screenBlock(entry) {
  const en = entry.en ? shot(entry.en) : null;
  const ne = entry.ne ? shot(entry.ne) : null;
  const out = [];

  out.push(
    new Paragraph({
      spacing: { before: 200, after: 60 },
      children: [txt(entry.label, { bold: true, size: 21, color: BRAND })],
    }),
  );
  if (entry.note) out.push(p(entry.note, { color: MUTED, size: 18, after: 80 }));

  if (!en && !ne) {
    out.push(missing(2));
    return out;
  }

  const col = (img, caption) =>
    cell(
      [
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 40 },
          children: img ? [img] : [txt('(not captured)', { color: MUTED, italics: true })],
        }),
        new Paragraph({
          alignment: AlignmentType.CENTER,
          spacing: { after: 0 },
          children: [txt(caption, { color: MUTED, size: 17 })],
        }),
      ],
      { width: 50 },
    );

  out.push(
    new Table({
      width: { size: 100, type: WidthType.PERCENTAGE },
      borders: NO_BORDER,
      rows: [new TableRow({ children: [col(en, 'English'), col(ne, 'नेपाली')] })],
    }),
  );
  return out;
}

// --- document --------------------------------------------------------------

function titlePage(meta) {
  return [
    new Paragraph({ spacing: { before: 1400, after: 0 }, children: [] }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 80 },
      children: [txt(meta.app, { bold: true, size: 56, color: BRAND })],
    }),
    new Paragraph({
      alignment: AlignmentType.CENTER,
      spacing: { after: 600 },
      children: [txt(meta.subtitle, { size: 28, color: MUTED })],
    }),
    table(
      ['Field', 'Value'],
      [
        ['Date', meta.date],
        ['Device', meta.device],
        ['Android', meta.android],
        ['Screen', meta.screen],
        ['APK', meta.apk],
        ['APK size', meta.apkSize],
        ['Build flags', meta.flags],
        ['flutter analyze', meta.analyze],
        ['flutter test', meta.tests],
      ],
      [30, 70],
    ),
    new Paragraph({ children: [new PageBreak()] }),
  ];
}

function build() {
  const children = [];

  children.push(...titlePage(data.meta));

  // 1 — what is done
  children.push(h1('1. What is done'));
  children.push(p(data.section1.intro));
  children.push(
    table(
      ['Screen', 'Restyled', 'Verified on device', 'Note'],
      data.section1.rows,
      [26, 14, 18, 42],
    ),
  );

  // 2 — functional checks
  children.push(h1('2. Functional checks'));
  children.push(p(data.section2.intro));
  children.push(
    table(['#', 'Check', 'Result', 'Note'], data.section2.rows, [6, 30, 12, 52]),
  );

  // 3 — defects fixed
  children.push(h1('3. Defects found and fixed'));
  children.push(p(data.section3.intro));
  for (const d of data.section3.items) {
    children.push(h2(`${d.id} — ${d.what}`));
    children.push(
      table(
        ['Field', 'Detail'],
        [
          ['Where', d.where],
          ['Symptom', d.symptom],
          ['Cause', d.cause],
          ['Fix', d.fix],
          ['Proof', d.proof],
        ],
        [18, 82],
      ),
    );
  }

  // 4 — what keeps failing
  children.push(h1('4. What keeps failing'));
  children.push(p(data.section4.intro));
  if (!data.section4.items.length) {
    children.push(p('No open failures.', { bold: true, color: GREEN }));
  }
  for (const f of data.section4.items) {
    children.push(h2(`${f.id} — ${f.what}`));
    children.push(
      table(
        ['Field', 'Detail'],
        [
          ['Severity', f.severity],
          ['Reproduce', f.repro],
          ['Error / evidence', f.error],
          ['Best guess at cause', f.cause],
          ['Suggested fix', f.fix],
        ],
        [22, 78],
      ),
    );
  }

  // 5 — screens
  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(h1('5. Screens'));
  children.push(p(data.section5.intro));
  for (const entry of data.section5.screens) {
    children.push(...screenBlock(entry));
  }

  // 6 — ready for the demo
  children.push(new Paragraph({ children: [new PageBreak()] }));
  children.push(h1('6. Ready for the demo?'));
  children.push(p(data.section6.verdict));
  children.push(h2('Pre-demo checklist for this phone'));
  for (const item of data.section6.checklist) {
    children.push(
      new Paragraph({
        spacing: { after: 90 },
        bullet: { level: 0 },
        children: [txt(item)],
      }),
    );
  }

  const doc = new Document({
    creator: 'Mero Swasthya verification run',
    title: 'End-user verification report',
    description: 'Patient-phone verification of the restyled Mero Swasthya app',
    styles: {
      default: {
        document: { run: { font: 'Calibri', size: 20, color: INK } },
      },
    },
    sections: [{ properties: {}, children }],
  });

  return Packer.toBuffer(doc).then((buf) => {
    fs.writeFileSync(OUT, buf);
    const kb = (buf.length / 1024).toFixed(0);
    console.log(`wrote ${OUT} (${kb} KB)`);
    if (buf.length < 20000) {
      console.error('WARNING: document looks too small — check the content');
      process.exitCode = 1;
    }
  });
}

build().catch((e) => {
  console.error(e);
  process.exit(1);
});
