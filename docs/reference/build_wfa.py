"""Turn WHO's simplified field tables into assets/who_wfa.json.

Source PDFs are downloaded verbatim from cdn.who.int; this only reshapes them.
Every check below is a check on the *source*, not on our transcription: if WHO
ever reissues a table with a different shape, this refuses to write.
"""
import io
import json
import re
import sys

import pypdfium2 as pdfium

ROW = re.compile(
    r'^\s*(\d+):\s*(\d+)\s+(\d+)\s+'
    r'([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s+([\d.]+)\s*$'
)

COLS = ['sd3neg', 'sd2neg', 'sd1neg', 'median', 'sd1pos', 'sd2pos', 'sd3pos']


def parse(path):
    doc = pdfium.PdfDocument(path)
    rows = {}
    for i in range(len(doc)):
        for line in doc[i].get_textpage().get_text_range().splitlines():
            m = ROW.match(line)
            if not m:
                continue
            year, month, months = int(m.group(1)), int(m.group(2)), int(m.group(3))
            assert year * 12 + month == months, f'{path}: {line!r} year/month disagree'
            assert months not in rows, f'{path}: month {months} appears twice'
            rows[months] = {
                'ageMonths': months,
                **{c: float(m.group(4 + n)) for n, c in enumerate(COLS)},
            }
    return [rows[m] for m in sorted(rows)]


def check(name, rows):
    assert [r['ageMonths'] for r in rows] == list(range(61)), \
        f'{name}: expected months 0..60, got {len(rows)} rows'
    for r in rows:
        ordered = [r[c] for c in COLS]
        assert ordered == sorted(ordered), f'{name}: month {r["ageMonths"]} z-scores out of order'
    for a, b in zip(rows, rows[1:]):
        for c in COLS:
            assert b[c] >= a[c], f'{name}: {c} falls between month {a["ageMonths"]} and {b["ageMonths"]}'
    print(f'{name}: {len(rows)} rows, months {rows[0]["ageMonths"]}-{rows[-1]["ageMonths"]}, all monotonic')


# Values printed in WHO's own charts and in every paediatric text. If the parse
# silently grabbed the wrong column these will not line up.
ANCHORS = {
    'male':   {0: (2.5, 3.3, 4.4), 12: (7.7, 9.6, 12.0), 24: (9.7, 12.2, 15.3), 60: (14.1, 18.3, 24.2)},
    'female': {0: (2.4, 3.2, 4.2), 12: (7.0, 8.9, 11.5), 24: (9.0, 11.5, 14.8), 60: (13.7, 18.2, 24.9)},
}


def main():
    series = {'male': parse('sft-boys.pdf'), 'female': parse('sft-girls.pdf')}
    for name, rows in series.items():
        check(name, rows)
        by_month = {r['ageMonths']: r for r in rows}
        for month, (neg, med, pos) in ANCHORS[name].items():
            r = by_month[month]
            got = (r['sd2neg'], r['median'], r['sd2pos'])
            assert got == (neg, med, pos), f'{name} month {month}: expected {(neg, med, pos)}, parsed {got}'
        print(f'{name}: all {len(ANCHORS[name])} anchor months match the published values')

    doc = {
        '_comment': (
            'THE OFFICIAL WHO CHILD GROWTH STANDARDS, weight-for-age, birth to 5 years, '
            'z-scores. Transcribed by machine from WHO\'s own simplified field tables '
            '(see `source`) on 2026-09-19 - no value here was typed by hand or fitted to '
            'a curve. This replaces the hand-fitted illustrative band the app shipped '
            'before. Weight-for-age alone cannot separate a short child from a wasted '
            'one; it is a screening curve, not a diagnosis, and the screen says so.'
        ),
        'version': 'who-cgs-wfa-2006.sft.2026-09-19',
        'standard': 'WHO Child Growth Standards (2006), weight-for-age z-scores',
        'source': {
            'retrievedOn': '2026-09-19',
            'method': 'Parsed straight out of the PDFs with pypdfium2; checked for 61 monthly rows per sex, z-score columns in order, monotonic growth, and four anchor months per sex against the published values.',
            'files': [
                'https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/sft-wfa-boys-z-0-5.pdf',
                'https://cdn.who.int/media/docs/default-source/child-growth/child-growth-standards/indicators/weight-for-age/sft-wfa-girls-z-0-5.pdf',
            ],
            'precision': 'WHO rounds the simplified field tables to 0.1 kg. That is the precision a health post weighs to, and it is the precision reproduced here.',
        },
        'unit': 'kg',
        'ageMonthsMin': 0,
        'ageMonthsMax': 60,
        'note': 'The app draws median and +/-2 SD. The -3 SD column (severely underweight) and the 1 and 3 SD columns are carried so the asset is a faithful copy of the source and a later feature needs no new download.',
        'series': series,
    }

    out = 'who_wfa.json'
    io.open(out, 'w', encoding='utf-8', newline='\n').write(
        json.dumps(doc, indent=2, ensure_ascii=False) + '\n'
    )
    print(f'wrote {out}')


if __name__ == '__main__':
    sys.exit(main())
