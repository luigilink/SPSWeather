(function () {
  'use strict';

  var errorBox = document.getElementById('spsw-error');
  function fail(message) {
    errorBox.textContent = 'SPSWeather cockpit: ' + message;
    errorBox.hidden = false;
  }
  window.addEventListener('error', function (e) { fail(e.message); });

  var D, PG;
  try {
    D = JSON.parse(document.getElementById('spsw-data').textContent);
    PG = JSON.parse(document.getElementById('spsw-page').textContent);
  } catch (e) { fail('the data embedded in the page cannot be read (' + e.message + ').'); return; }
  if (!D || D.schemaVersion !== 1 || !Array.isArray(D.days) || !Array.isArray(D.farms)) { fail('the data embedded in the page is not in a supported format.'); return; }

  const TABS = ['direction', 'it', 'quality', 'runs', 'method'];
  const NO_BREAK = '\u00a0';
  const ESC = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
  const days = D.days, N = days.length, farms = D.farms;
  const cultures = Object.keys(PG.cultures);
  const offered = D.period && Array.isArray(D.period.offered) && D.period.offered.length ? D.period.offered.map(Number) : [N];

  /* ---------- safe HTML: every interpolated value is escaped unless it comes from h() or raw() ---------- */
  function Raw(s) { this.s = s; }
  function raw(s) { return new Raw(s); }
  function esc(s) { return String(s === null || s === undefined ? '' : s).replace(/[&<>"']/g, function (c) { return ESC[c]; }); }
  function part(v) { return v instanceof Raw ? v.s : Array.isArray(v) ? v.map(part).join('') : esc(v); }
  function h(strings) {
    let out = strings[0];
    for (let i = 1; i < arguments.length; i++) out += part(arguments[i]) + strings[i];
    return new Raw(out);
  }

  /* ---------- state kept in the URL hash: lang, theme, p (period), tab ---------- */
  const DEFAULTS = { lang: PG.language, theme: '', p: String(offered.indexOf(30) >= 0 ? 30 : Math.max.apply(null, offered)), tab: 'direction' };
  const VALID = {
    lang: function (v) { return cultures.indexOf(v) >= 0; },
    theme: function (v) { return v === 'light' || v === 'dark'; },
    p: function (v) { return offered.map(String).indexOf(v) >= 0; },
    tab: function (v) { return TABS.indexOf(v) >= 0; }
  };
  const state = Object.assign({}, DEFAULTS);
  function readHash() {
    Object.assign(state, DEFAULTS);
    location.hash.replace(/^#/, '').split('&').forEach(function (pair) {
      const i = pair.indexOf('=');
      if (i < 1) return;
      const key = pair.slice(0, i);
      let value;
      try { value = decodeURIComponent(pair.slice(i + 1)); } catch (e) { return; }
      if (VALID[key] && VALID[key](value)) state[key] = value;
    });
  }
  function hashFor(change) {
    const next = Object.assign({}, state, change || {});
    const parts = Object.keys(DEFAULTS).filter(function (k) { return next[k] !== DEFAULTS[k]; })
      .map(function (k) { return k + '=' + encodeURIComponent(next[k]); });
    return parts.length ? '#' + parts.join('&') : '#';
  }
  function writeHash() {
    // Some browsers refuse replaceState on file:// addresses: the state then stays in memory only.
    try { history.replaceState(null, '', hashFor()); } catch (e) { /* ignore */ }
  }

  /* ---------- strings and formats ---------- */
  function t(key) {
    const args = arguments;
    const current = PG.cultures[state.lang].text, reference = PG.cultures[PG.fallback].text;
    const s = typeof current[key] === 'string' ? current[key] : reference[key];
    if (typeof s !== 'string') return key;
    return s.replace(/\{(\d+)\}/g, function (m, i) { return +i + 1 < args.length ? args[+i + 1] : m; });
  }
  function hasKey(key) { return typeof PG.cultures[state.lang].text[key] === 'string' || typeof PG.cultures[PG.fallback].text[key] === 'string'; }
  function locale() {
    try { new Intl.DateTimeFormat(state.lang); return state.lang; } catch (e) { return PG.fallback; }
  }
  function n0(v) { return Number(v).toLocaleString(locale(), { maximumFractionDigits: 0 }); }
  function n1(v) { return Number(v).toLocaleString(locale(), { minimumFractionDigits: 1, maximumFractionDigits: 1 }); }
  function pct(v, d) { return t('Percent', d === 0 ? n0(v) : n1(v)); }
  function pctOrDash(v, d) { return v === null ? '\u2014' : pct(v, d); }
  function pts(v) { return t('CockpitPoints', n1(v)); }
  function dayCount(v) { return t('CockpitDaysShort', n0(v)); }
  function dayFmt(iso, options) { return new Date(iso + 'T12:00:00Z').toLocaleDateString(locale(), Object.assign({ timeZone: 'UTC' }, options)); }
  function dshort(iso) { return dayFmt(iso, { day: '2-digit', month: '2-digit' }); }
  function dlong(iso) { return dayFmt(iso, { weekday: 'short', day: '2-digit', month: 'short' }); }
  function dfull(iso) { return dayFmt(iso, { day: '2-digit', month: 'long', year: 'numeric' }); }
  function stamp(iso) { return dshort(iso.slice(0, 10)) + ' ' + iso.slice(11, 16); }
  function daysBetween(a, b) { return Math.round((new Date(b + 'T12:00:00Z') - new Date(a + 'T12:00:00Z')) / 86400000); }
  function minSec(seconds) { return Math.floor(seconds / 60) + NO_BREAK + t('CockpitMinutes') + NO_BREAK + ('0' + (seconds % 60)).slice(-2) + 's'; }

  /* ---------- the figures of the data ---------- */
  function hasData(c) { return !!c && c.ok !== null; }
  function cellState(c) { return !c ? 'none' : c.ok === null ? 'down' : c.fail > 0 ? 'fail' : c.warn > 0 ? 'warn' : 'ok'; }
  function worstOf(list) {
    const rank = { none: 0, ok: 1, warn: 2, fail: 3, down: 4 };
    return list.reduce(function (a, b) { return rank[b] > rank[a] ? b : a; }, 'none');
  }
  function latest(f) {
    for (let i = N - 1; i >= 0; i--) if (hasData(f.daily[i])) return { i: i, c: f.daily[i] };
    return null;
  }
  function latestDay(f) { const l = latest(f); return l ? days[l.i] : null; }
  function addCounts(list) {
    return list.reduce(function (s, c) { return { ok: s.ok + c.ok, warn: s.warn + c.warn, fail: s.fail + c.fail }; }, { ok: 0, warn: 0, fail: 0 });
  }
  function globalDay(i) {
    const cells = farms.map(function (f) { return f.daily[i]; }).filter(hasData);
    return cells.length ? addCounts(cells) : null;
  }
  const GLOBAL = days.map(function (d, i) { return globalDay(i); });
  function healthPct(r) { const total = r ? r.ok + r.warn + r.fail : 0; return total ? r.ok / total * 100 : null; }
  function average(list) { const v = list.filter(function (x) { return x !== null; }); return v.length ? v.reduce(function (a, b) { return a + b; }, 0) / v.length : null; }
  function range() { const p = Math.min(+state.p || N, N); return { from: N - p, to: N, len: p }; }
  function prevRange() { const r = range(); return r.from - r.len < 0 ? null : { from: r.from - r.len, to: r.from, len: r.len }; }
  function averageHealth(r) { return average(GLOBAL.slice(r.from, r.to).map(healthPct)); }
  function snapshotDay(i) { return farms.some(function (f) { return hasData(f.daily[i]); }); }
  function cleanDay(i) {
    let any = false;
    for (let k = 0; k < farms.length; k++) {
      const c = farms[k].daily[i];
      if (!c) continue;
      if (c.ok === null || c.fail > 0 || c.unreachable > 0) return false;
      any = true;
    }
    return any;
  }
  function cleanStats(r) {
    let eligible = 0, clean = 0;
    for (let i = r.from; i < r.to; i++) { if (snapshotDay(i)) eligible++; if (cleanDay(i)) clean++; }
    return { eligible: eligible, clean: clean, rate: eligible ? clean / eligible * 100 : null };
  }
  function collection(r) {
    let expected = 0, collected = 0, unreachable = 0;
    farms.forEach(function (f) {
      let first = -1;
      for (let i = 0; i < N; i++) if (f.daily[i]) { first = i; break; }
      if (first < 0) return;
      for (let i = Math.max(first, r.from); i < r.to; i++) {
        expected++;
        if (hasData(f.daily[i])) collected++; else if (f.daily[i]) unreachable++;
      }
    });
    return { expected: expected, collected: collected, unreachable: unreachable, rate: expected ? collected / expected * 100 : null };
  }
  function compare(a, b) { return a < b ? -1 : a > b ? 1 : 0; }
  function attentionList() {
    return [].concat.apply([], farms.map(function (f) { return f.attention; })).sort(function (a, b) {
      return (a.severity === b.severity ? 0 : a.severity === 'fail' ? -1 : 1) || compare(a.since, b.since) || compare(a.farm, b.farm) || compare(a.name, b.name);
    });
  }
  function farmOf(a) { return farms.filter(function (f) { return f.name === a.farm; })[0]; }
  function isNew(a) { const f = farmOf(a); return !a.sinceIsLowerBound && !!f && a.since === latestDay(f); }
  function sectionLabel(id) { return hasKey('Section_' + id) ? t('Section_' + id) : id; }
  function weatherKey(c) { return c && c.weather ? c.weather : 'sunny'; }
  function weatherOf(states) {
    const order = ['sunny', 'fair', 'cloudy', 'stormy'];
    return states.reduce(function (a, b) { return order.indexOf(b) > order.indexOf(a) ? b : a; }, 'sunny');
  }
  const WEATHER = { sunny: ['\u2600\ufe0f', 'WeatherSunny'], fair: ['\ud83c\udf24\ufe0f', 'WeatherFair'], cloudy: ['\u26c5', 'WeatherCloudy'], stormy: ['\u26c8\ufe0f', 'WeatherStormy'] };
  const STATUS = { ok: 'FarmStatusOk', warn: 'FarmStatusWarn', fail: 'FarmStatusAlert', down: 'FarmStatusDown' };

  /* ---------- small components ---------- */
  function badge(st) { return h`<span class="badge b-${st}">${t(STATUS[st])}</span>`; }
  function counts(c) { return t('CountsSummary', c.ok, c.warn, c.fail); }
  function kpi(cls, label, value, sub, chip, extra) {
    return h`<div class="card kpi ${cls}"><span class="l">${label}</span><span class="v num">${value}</span><span class="sub">${sub}</span>${chip ? h`<div>${chip}</div>` : ''}${extra}</div>`;
  }
  function asof(text) { return h`<div class="asof">${text}</div>`; }
  function cta(label, tab) { return h`<a class="cta" href="${hashFor({ tab: tab })}" data-tab="${tab}">${label} \u2192</a>`; }
  function delta(cur, prev, o) {
    if (cur === null || prev === null || prev === undefined || isNaN(prev)) return h`<span class="delta flat">${t('CockpitNoPrevious')}</span>`;
    const d = cur - prev, flat = Math.abs(d) < (o.eps === undefined ? 0.05 : o.eps), up = d > 0, good = o.better === 'up' ? up : !up;
    return h`<span class="delta ${flat ? 'flat' : good ? 'good' : 'bad'}" title="${t('CockpitVsPrevious')}">${flat ? '\u2192' : up ? '\u2191' : '\u2193'} ${o.fmt(Math.abs(d))}</span>`;
  }
  function empty(text) { return h`<div class="card empty">${text}</div>`; }
  function sinceText(a) { return a.sinceIsLowerBound ? t('CockpitSinceOrBefore', dshort(a.since)) : t('CockpitSince', dshort(a.since)); }
  function table(head, rows, cls) {
    return h`<div class="scroll"><table class="t ${cls || ''}"><thead><tr>${head.map(function (c) { return h`<th class="${c.r ? 'r' : ''}">${c.label}</th>`; })}</tr></thead><tbody>${rows}</tbody></table></div>`;
  }

  /* ---------- SVG charts (inline, no library) ---------- */
  const PL = 52, PR = 12, PT = 12, PB = 26;
  function chartWidth(wide) { return window.innerWidth < 700 ? 380 : wide ? 1100 : 760; }
  function xTicks(n, x, hh, Wd) {
    const every = Math.max(1, Math.round(n / (Wd < 500 ? 5 : 10))), out = [];
    for (let i = 0; i < n; i += every) out.push(h`<text x="${x(i).toFixed(1)}" y="${hh - 7}" text-anchor="middle">${dshort(days[N - n + i])}</text>`);
    return out;
  }
  function stackBars(rows, from, label) {
    const W = chartWidth(false), n = rows.length, hh = 230, bw = (W - PL - PR) / n, gap = Math.min(3, bw * 0.18), inner = hh - PB - PT;
    const x = function (i) { return PL + i * bw + bw / 2; };
    const grid = [0, 50, 100].map(function (v) {
      const y = (PT + inner * (1 - v / 100)).toFixed(1);
      return h`<line x1="${PL}" x2="${W - PR}" y1="${y}" y2="${y}" stroke="var(--grid)"/><text x="${PL - 6}" y="${+y + 4}" text-anchor="end">${pct(v, 0)}</text>`;
    });
    const bars = rows.map(function (r, i) {
      const day = days[from + i], x0 = (PL + i * bw + gap / 2).toFixed(1), w = (bw - gap).toFixed(1);
      const band = D.weekend && D.weekend[from + i] ? h`<rect x="${(PL + i * bw).toFixed(1)}" y="${PT}" width="${bw.toFixed(1)}" height="${inner}" fill="var(--weekend)"/>` : '';
      if (!r) return h`${band}<rect x="${x0}" y="${PT}" width="${w}" height="${inner}" fill="transparent"><title>${dlong(day) + ' \u2014 ' + t('CockpitNoSnapshot')}</title></rect>`;
      const total = r.ok + r.warn + r.fail;
      if (!total) return h`${band}<rect x="${x0}" y="${PT}" width="${w}" height="${inner}" fill="transparent"><title>${t('BarTip', dlong(day), 0, 0, 0)}</title></rect>`;
      let yb = hh - PB;
      const segments = [['var(--fail)', r.fail], ['var(--warn)', r.warn], ['var(--ok)', r.ok]].map(function (p) {
        const height = inner * p[1] / total;
        if (height <= 0) return '';
        yb -= height;
        return h`<rect x="${x0}" y="${yb.toFixed(1)}" width="${w}" height="${height.toFixed(1)}" fill="${p[0]}"/>`;
      });
      return h`${band}${segments}<rect x="${x0}" y="${PT}" width="${w}" height="${inner}" fill="transparent"><title>${t('BarTip', dlong(day), r.ok, r.warn, r.fail)}</title></rect>`;
    });
    return h`<svg class="chart" viewBox="0 0 ${W} ${hh}" role="img" aria-label="${label}">${grid}${bars}${xTicks(n, x, hh, W)}</svg>`;
  }
  function lineChart(values, from, fmt, axis, label) {
    const W = chartWidth(true), n = values.length, hh = 190, present = values.filter(function (v) { return v !== null; });
    if (!present.length) return '';
    const top = Math.max.apply(null, present) * 1.15 || 1, inner = hh - PB - PT;
    const x = function (i) { return PL + 6 + (n > 1 ? i / (n - 1) : 0.5) * (W - PL - PR - 12); };
    const y = function (v) { return PT + inner * (1 - v / top); };
    let path = '', started = false;
    values.forEach(function (v, i) {
      if (v === null) { started = false; return; }
      path += (started ? 'L' : 'M') + x(i).toFixed(1) + ' ' + y(v).toFixed(1);
      started = true;
    });
    const grid = [0, 1, 2, 3, 4].map(function (k) {
      const v = top * k / 4, yy = y(v).toFixed(1);
      return h`<line x1="${PL}" x2="${W - PR}" y1="${yy}" y2="${yy}" stroke="var(--grid)"/><text x="${PL - 6}" y="${+yy + 4}" text-anchor="end">${axis(v)}</text>`;
    });
    const dots = values.map(function (v, i) {
      return v === null ? '' : h`<circle cx="${x(i).toFixed(1)}" cy="${y(v).toFixed(1)}" r="3" fill="var(--blue)"><title>${dlong(days[from + i]) + ' \u2014 ' + fmt(v)}</title></circle>`;
    });
    return h`<svg class="chart" viewBox="0 0 ${W} ${hh}" role="img" aria-label="${label}">${grid}<path d="${path}" fill="none" stroke="var(--blue)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>${dots}${xTicks(n, x, hh, W)}</svg>`;
  }
  function spark(values, color) {
    const present = values.filter(function (v) { return v !== null; });
    if (present.length < 2) return '';
    const w = 120, hh = 30, n = values.length;
    let path = '';
    values.forEach(function (v, i) {
      if (v === null) return;
      path += (path ? 'L' : 'M') + (2 + i / (n - 1) * (w - 4)).toFixed(1) + ' ' + (3 + (1 - Math.max(0, Math.min(1, (v - 60) / 40))) * (hh - 6)).toFixed(1);
    });
    return h`<svg width="${w}" height="${hh}" viewBox="0 0 ${w} ${hh}" aria-hidden="true"><path d="${path}" fill="none" stroke="${color}" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/></svg>`;
  }
  function donut(c, label) {
    const sum = c.ok + c.warn + c.fail, total = sum || 1, r = 52, circ = 2 * Math.PI * r;
    let offset = 0;
    const arcs = [['var(--ok)', c.ok], ['var(--warn)', c.warn], ['var(--fail)', c.fail]].map(function (p) {
      const len = circ * p[1] / total;
      if (len <= 0) return '';
      const arc = h`<circle cx="70" cy="70" r="${r}" fill="none" stroke="${p[0]}" stroke-width="16" stroke-dasharray="${len.toFixed(2)} ${(circ - len).toFixed(2)}" stroke-dashoffset="${(-offset).toFixed(2)}" transform="rotate(-90 70 70)"/>`;
      offset += len;
      return arc;
    });
    return h`<svg width="150" height="150" viewBox="0 0 140 140" role="img" aria-label="${label}">${arcs}<text x="70" y="76" text-anchor="middle" style="fill:var(--text);font-size:26px;font-weight:800">${sum ? pct(c.ok / total * 100, 0) : '\u2014'}</text></svg>`;
  }
  function hbar(c) {
    const total = c.ok + c.warn + c.fail || 1;
    return h`<div class="hbar" role="img" aria-label="${counts(c)}"><i class="o" style="width:${(c.ok / total * 100).toFixed(2)}%"></i><i class="w" style="width:${(c.warn / total * 100).toFixed(2)}%"></i><i class="f" style="width:${(c.fail / total * 100).toFixed(2)}%"></i></div>`;
  }
  function legend(items) {
    return h`<div class="legend">${items.map(function (i) { return h`<span><i style="background:var(--${i[0]})"></i>${i[1]}</span>`; })}</div>`;
  }


  /* ---------- insight sentences: fixed rules on the data, nothing else ---------- */
  function say(tone, key) { return { tone: tone, text: t.apply(null, [key].concat([].slice.call(arguments, 2))) }; }
  function insightHtml(i) { return i ? h`<div class="insight ${i.tone}">${i.text}</div>` : ''; }
  function lastDataIndex(r) { for (let i = r.to - 1; i >= r.from; i--) if (snapshotDay(i)) return i; return -1; }
  function topGroup(items, keyOf, labelOf) {
    const groups = {};
    items.forEach(function (a) { const k = keyOf(a); (groups[k] = groups[k] || { key: k, label: labelOf(a), items: 0, count: 0 }); groups[k].items++; groups[k].count += a.count; });
    return Object.keys(groups).map(function (k) { return groups[k]; }).sort(function (a, b) { return b.items - a.items || compare(a.key, b.key); })[0] || null;
  }
  function insightHealth(ctx) {
    if (ctx.nowPct === null) return null;
    let head;
    if (ctx.prevAvg !== null) {
      const diff = ctx.nowPct - ctx.prevAvg;
      head = diff <= -1 ? say('bad', 'CockpitInsightHealthDown', pts(Math.abs(diff))) : diff >= 1 ? say('good', 'CockpitInsightHealthUp', pts(diff)) : say('', 'CockpitInsightHealthStable');
    } else head = ctx.now.fail > 0 ? say('bad', 'CockpitInsightHealthFail', ctx.now.fail) : ctx.now.warn > 0 ? say('warn', 'CockpitInsightHealthWarn', ctx.now.warn) : say('good', 'CockpitInsightClear');
    const failing = ctx.open.filter(function (a) { return a.severity === 'fail'; });
    const top = ctx.complete && failing.length >= 2 ? topGroup(failing, function (a) { return a.section; }, function (a) { return sectionLabel(a.section); }) : null;
    if (top && top.items * 2 > failing.length) return { tone: head.tone, text: head.text + ' ' + t('CockpitInsightTopSection', top.label) };
    return head;
  }
  function insightClean(ctx) {
    const r = ctx.r, last = lastDataIndex(r);
    if (last < 0) return null;
    if (cleanDay(last)) return say('good', 'CockpitInsightCleanLast', dshort(days[last]));
    for (let i = last - 1; i >= r.from; i--) if (cleanDay(i)) return say('warn', 'CockpitInsightCleanSince', dshort(days[i]), daysBetween(days[i], days[last]));
    return say('bad', 'CockpitInsightCleanNone');
  }
  function insightOpen(ctx) {
    const open = ctx.open;
    if (!open.length) return say('good', 'CockpitNothingOpen');
    const top = ctx.complete ? topGroup(open, function (a) { return a.section + '|' + a.cause; }, function (a) { return a.cause; }) : null;
    if (top && top.items >= 2 && top.items * 2 >= open.length) return say('warn', 'CockpitInsightOpenCause', top.items, open.length, top.label);
    const oldest = open.slice().sort(function (a, b) { return compare(a.since, b.since) || (a.severity === b.severity ? 0 : a.severity === 'fail' ? -1 : 1) || compare(a.farm, b.farm) || compare(a.name, b.name); })[0];
    if (oldest.sinceIsLowerBound) return say('warn', 'CockpitInsightOpenOldestLower', oldest.name, dshort(oldest.since));
    const f = farmOf(oldest), age = f && latestDay(f) ? daysBetween(oldest.since, latestDay(f)) : 0;
    return age > 0 ? say('warn', 'CockpitInsightOpenOldest', oldest.name, age, dshort(oldest.since)) : say('warn', 'CockpitInsightOpenAllNew');
  }
  function insightCollection(ctx) {
    const r = ctx.r, coll = ctx.coll;
    if (!coll.expected) return null;
    let down = null, downDays = 0;
    farms.forEach(function (f) {
      for (let i = r.from; i < r.to; i++) {
        const c = f.daily[i];
        if (c && c.ok === null) { downDays++; if (!down || i >= down.i) down = { i: i, farm: f.name }; }
      }
    });
    if (down) return downDays === 1 ? say('warn', 'CockpitInsightCollectDown', down.farm, dshort(days[down.i])) : say('warn', 'CockpitInsightCollectDownMany', down.farm, dshort(days[down.i]), downDays);
    const missing = coll.expected - coll.collected;
    return missing > 0 ? say('warn', 'CockpitInsightCollectMissing', missing, coll.expected) : say('good', 'CockpitInsightCollectAll');
  }
  function firstDataDay(f) { for (let i = 0; i < N; i++) if (hasData(f.daily[i])) return days[i]; return null; }
  function failureStreak(f) {
    let since = null;
    for (let i = N - 1; i >= 0; i--) {
      const c = f.daily[i];
      if (!hasData(c)) continue;
      if (c.fail > 0) since = days[i]; else break;
    }
    return { since: since, reachedStart: since !== null && since === firstDataDay(f) };
  }
  function insightWeather(ctx) {
    if (!ctx.latests.length) return null;
    const rows = farms.map(function (f) { return { f: f, l: latest(f) }; }).filter(function (p) { return p.l; });
    const worst = rows.slice().sort(function (a, b) { return b.l.c.fail - a.l.c.fail || compare(a.f.name, b.f.name); })[0];
    if (worst.l.c.fail > 0) {
      const s = failureStreak(worst.f);
      return say('bad', s.reachedStart ? 'CockpitInsightWeatherSinceLower' : 'CockpitInsightWeatherSince', worst.f.name, dshort(s.since));
    }
    if (ctx.now.warn > 0) return say('warn', 'CockpitInsightWeatherWarn', ctx.now.warn);
    return say('good', 'CockpitInsightClear');
  }

  /* ---------- Direction ---------- */
  function attentionRow(a) {
    const f = farmOf(a), age = !a.sinceIsLowerBound && f ? daysBetween(a.since, latestDay(f)) : null;
    return h`<tr><td><span class="badge b-${a.severity}">${t(a.severity === 'fail' ? 'ShortFail' : 'ShortWarn')}</span></td><td class="wrap-cell"><b>${a.name}</b>${a.count > 1 ? h` <span class="muted">\u00d7${a.count}</span>` : ''}${isNew(a) ? h` <span class="badge b-new">${t('CockpitNew')}</span>` : ''}</td><td>${a.farm}</td><td>${sectionLabel(a.section)}</td><td class="wrap-cell">${a.detail || a.cause}</td><td class="num">${sinceText(a)}${age ? ' \u00b7 ' + dayCount(age) : ''}</td></tr>`;
  }
  function attentionHead() {
    return [{ label: t('CockpitSeverity') }, { label: t('CockpitItem') }, { label: t('FarmLabel') }, { label: t('CockpitSection') }, { label: t('CockpitDetail') }, { label: t('CockpitSinceCol') }];
  }
  function farmCard(f, r) {
    const l = latest(f), lastCell = f.daily[N - 1];
    const st = lastCell && lastCell.ok === null ? 'down' : l ? cellState(l.c) : 'down';
    const series = []; for (let i = r.from; i < r.to; i++) series.push(healthPct(hasData(f.daily[i]) ? f.daily[i] : null));
    let info = '';
    if (!l) info = t('CockpitNoSnapshot');
    else if (st === 'down') info = t('CockpitUnreachable', dshort(days[N - 1]));
    else {
      let lastFail = -1;
      for (let i = l.i; i >= 0; i--) { const c = f.daily[i]; if (c && (c.ok === null || c.fail > 0)) { lastFail = i; break; } }
      info = lastFail === l.i ? t('CockpitFailingNow') : lastFail < 0 ? t('CockpitNoFailure') : t('CockpitLastFailure', dshort(days[lastFail]));
      if (N - 1 - l.i >= 2) info += ' \u00b7 ' + t('CockpitNoSnapshotDays', N - 1 - l.i);
    }
    const color = st === 'ok' ? 'var(--ok)' : st === 'warn' ? 'var(--warn)' : st === 'fail' ? 'var(--fail)' : 'var(--down)';
    return h`<div class="card farm s-${st}"><div class="farm-hd"><div><h4>${f.name}</h4><small>${f.latestSnapshot ? stamp(f.latestSnapshot) : ''}</small></div>${badge(st)}</div>${l ? h`<div>${hbar(l.c)}<div class="row" style="margin-top:6px"><b class="num">${healthPct(l.c) === null ? '\u2014' : t('FarmHealth', pct(healthPct(l.c), 0))}</b><span class="small muted num">${counts(l.c)}</span></div></div>` : ''}<div class="row"><span class="small muted">${info}</span>${spark(series, color)}</div></div>`;
  }
  function viewDirection() {
    if (!farms.length || !GLOBAL.some(function (g) { return g; })) return empty(t('CockpitNoData'));
    const r = range(), pr = prevRange();
    const latests = farms.map(latest).filter(Boolean);
    const now = addCounts(latests.map(function (l) { return l.c; }));
    const nowPct = healthPct(now), prevAvg = pr ? averageHealth(pr) : null;
    const stateNow = worstOf(latests.map(function (l) { return cellState(l.c); }));
    const clean = cleanStats(r), cleanPrev = pr ? cleanStats(pr) : null;
    const open = attentionList(), openTotal = farms.reduce(function (s, f) { return s + f.attentionTotal; }, 0);
    const crit = open.filter(function (a) { return a.severity === 'fail'; }).length, newCount = open.filter(isNew).length;
    const coll = collection(r), collPrev = pr ? collection(pr) : null;
    const newest = farms.map(function (f) { return f.latestSnapshot; }).filter(Boolean).sort().pop();
    const snapshotAsOf = newest ? asof(t('CockpitAsOfSnapshot', stamp(newest))) : '';
    const periodAsOf = asof(t('CockpitAsOfPeriod', r.len, dshort(days[N - 1])));
    const tone = function (st) { return st === 'ok' ? 'ok' : st === 'warn' ? 'warn' : 'fail'; };
    const ctx = { r: r, now: now, nowPct: nowPct, prevAvg: prevAvg, open: open, coll: coll, latests: latests, complete: farms.every(function (f) { return !f.attentionTruncated; }) };

    const kpis = h`<div class="grid g4">${[
      kpi(tone(stateNow), t('CockpitKpiHealth'), pctOrDash(nowPct, 1), counts(now), delta(nowPct, prevAvg, { better: 'up', fmt: pts }), h`${insightHtml(insightHealth(ctx))}${snapshotAsOf}${cta(t('CockpitCtaStability'), 'it')}`),
      kpi(clean.rate === null ? 'blue' : clean.rate >= 80 ? 'ok' : clean.rate >= 50 ? 'warn' : 'fail', t('CockpitKpiCleanDays'), h`${clean.clean}<small class="faint" style="font-size:16px"> / ${clean.eligible}</small>`, t('CockpitKpiCleanSub', r.len), cleanPrev ? delta(clean.rate, cleanPrev.rate, { better: 'up', fmt: pts, eps: 0.5 }) : delta(null, null, {}), h`${insightHtml(insightClean(ctx))}${periodAsOf}${cta(t('CockpitCtaStability'), 'it')}`),
      kpi(crit ? 'fail' : openTotal ? 'warn' : 'ok', t('CockpitKpiOpen'), n0(openTotal), t('CockpitKpiOpenSub', crit, open.length - crit), newCount ? h`<span class="delta bad">${t('CockpitNewCount', newCount)}</span>` : '', h`${insightHtml(insightOpen(ctx))}${snapshotAsOf}<a class="cta" href="#spsw-attention" data-scroll="spsw-attention">${t('CockpitCtaAttention')} \u2193</a>`),
      kpi('blue', t('CockpitKpiCollection'), coll.rate === null ? '\u2014' : pct(coll.rate, 1), t('CockpitKpiCollectionSub', coll.collected, coll.expected), collPrev ? delta(coll.rate, collPrev.rate, { better: 'up', fmt: pts, eps: 0.05 }) : delta(null, null, {}), h`${insightHtml(insightCollection(ctx))}${periodAsOf}${cta(t('CockpitCtaRuns'), 'runs')}`)
    ]}</div>`;

    const cards = farms.map(function (f) { return farmCard(f, r); });
    const rows = GLOBAL.slice(r.from, r.to);
    const wxKey = weatherOf(latests.map(function (l) { return weatherKey(l.c); })), wx = WEATHER[wxKey];
    const worst = farms.map(function (f) { return { name: f.name, c: (latest(f) || {}).c }; }).filter(function (p) { return p.c; }).sort(function (a, b) { return b.c.fail - a.c.fail; })[0];
    const trend = h`<div class="card"><h3>${t('CockpitAllFarms')}</h3>${stackBars(rows, r.from, t('CockpitTrend'))}${legend([['ok', t('ShortOk')], ['warn', t('LegendWarning')], ['fail', t('LegendFailure')]])}${periodAsOf}</div>`;
    const overview = h`<div class="card" style="display:flex;flex-direction:column;align-items:center;gap:6px;text-align:center"><h3 style="align-self:flex-start">${t('CockpitKpiHealth')}</h3>${donut(now, t('CockpitKpiHealth'))}<div style="font-size:30px;line-height:1">${wx[0]}</div><b>${t(wx[1])}</b>${worst && worst.c.fail ? h`<span class="small muted">${t('CockpitWeatherWhy', worst.name, worst.c.fail)}</span>` : ''}<div class="small muted num" style="margin-top:4px">${counts(now)}</div>${insightHtml(insightWeather(ctx))}${snapshotAsOf}</div>`;

    const top = open.slice(0, 10), rest = open.slice(10);
    const attention = open.length ? h`<div class="card"><h3>${t('CockpitListed', open.length, openTotal)}</h3>${table(attentionHead(), top.map(attentionRow))}${rest.length ? h`<details class="fold" style="margin-top:12px"><summary><span>${t('CockpitShowOthers', rest.length)}</span></summary><div class="in">${table(attentionHead(), rest.map(attentionRow))}</div></details>` : ''}</div>` : h`<div class="card"><h3>${t('CockpitSecAttention')}</h3><div class="empty">${t('AllClearTitle')} ${t('CockpitNothingOpen')}</div></div>`;

    return h`${kpis}<div class="sec-title">${t('CockpitSecFarms')}</div><div class="grid g3">${cards}</div><div class="sec-title">${t('CockpitSecTrend')}</div><div class="grid g-main">${trend}${overview}</div><div class="sec-title" id="spsw-attention">${t('CockpitSecAttention')}</div>${attention}`;
  }

  /* ---------- IT ---------- */
  function viewIT() {
    const open = attentionList(), r = range();
    const groups = {};
    open.forEach(function (a) {
      const key = a.section + '|' + a.cause;
      const g = groups[key] || (groups[key] = { section: a.section, cause: a.cause, count: 0, items: 0, farms: {}, since: a.since, lower: a.sinceIsLowerBound, severity: 'warn' });
      g.items++; g.count += a.count; g.farms[a.farm] = true;
      if (a.severity === 'fail') g.severity = 'fail';
      if (a.since < g.since) { g.since = a.since; g.lower = a.sinceIsLowerBound; }
    });
    const causeRows = Object.keys(groups).map(function (k) { return groups[k]; }).sort(function (a, b) { return (a.severity === b.severity ? 0 : a.severity === 'fail' ? -1 : 1) || b.items - a.items; });
    const causes = h`<div class="card"><h3>${t('CockpitSecCauses')}<small>${t('CockpitCausesHint')}</small></h3>${open.length ? table([{ label: t('CockpitSeverity') }, { label: t('CockpitSection') }, { label: t('CockpitCause') }, { label: t('CockpitItems'), r: true }, { label: t('CockpitFarms') }, { label: t('CockpitSinceCol') }], causeRows.map(function (g) {
      return h`<tr><td><span class="badge b-${g.severity}">${t(g.severity === 'fail' ? 'ShortFail' : 'ShortWarn')}</span></td><td>${sectionLabel(g.section)}</td><td class="wrap-cell">${g.cause}</td><td class="r num">${g.items}</td><td>${Object.keys(g.farms).join(', ')}</td><td class="num">${sinceText({ since: g.since, sinceIsLowerBound: g.lower })}</td></tr>`;
    })) : h`<div class="empty">${t('CockpitNothingOpen')}</div>`}</div>`;

    const sections = {};
    open.forEach(function (a) { sections[a.section] = (sections[a.section] || 0) + 1; });
    const ids = Object.keys(sections).sort(function (a, b) { return sections[b] - sections[a] || compare(a, b); });
    const cell = function (f, id) {
      const items = f.attention.filter(function (a) { return a.section === id; }), failing = items.filter(function (a) { return a.severity === 'fail'; }).length;
      return !items.length ? h`<span class="cell none">\u2013</span>` : failing ? h`<span class="cell fail">${failing} ${t('ShortFail')}</span>` : h`<span class="cell warn">${items.length} ${t('ShortWarn')}</span>`;
    };
    const matrix = h`<div class="card"><h3>${t('CockpitSecMatrix')}</h3>${ids.length ? h`<div class="scroll" style="max-height:none"><table class="t matrix"><thead><tr><th>${t('FarmLabel')}</th>${ids.map(function (id) { return h`<th>${sectionLabel(id)}</th>`; })}</tr></thead><tbody>${farms.map(function (f) { return h`<tr><td style="text-align:left"><b>${f.name}</b></td>${ids.map(function (id) { return h`<td>${cell(f, id)}</td>`; })}</tr>`; })}</tbody></table></div>` : h`<div class="empty">${t('CockpitNothingOpen')}</div>`}</div>`;

    const cw = Math.max(8, Math.min(22, Math.floor(900 / r.len)));
    const strips = farms.map(function (f) {
      const spans = [], rows = [], tally = { ok: 0, warn: 0, fail: 0, down: 0, none: 0 };
      for (let i = r.to - 1; i >= r.from; i--) {
        const c = f.daily[i], st = cellState(c);
        tally[st]++;
        rows.push(h`<tr><td class="num">${dlong(days[i])}</td><td>${st === 'none' ? t('CockpitNoSnapshot') : t(STATUS[st])}</td><td class="num">${st === 'ok' || st === 'warn' || st === 'fail' ? counts(c) : '\u2014'}</td><td class="r num">${c && c.unreachable > 0 ? n0(c.unreachable) : ''}</td></tr>`);
      }
      for (let i = r.from; i < r.to; i++) {
        const c = f.daily[i], st = cellState(c);
        const tip = dlong(days[i]) + ' \u2014 ' + (st === 'none' ? t('CockpitNoSnapshot') : st === 'down' ? t('FarmStatusDown') : counts(c));
        const bg = st === 'none' ? 'var(--line)' : 'var(--' + st + ')';
        spans.push(h`<span title="${tip}" style="width:${cw}px;background:${bg};${st === 'down' ? 'opacity:.55;' : ''}${D.weekend && D.weekend[i] ? 'outline:1px solid var(--weekend);' : ''}"></span>`);
      }
      const summary = f.name + ': ' + t('CockpitStripSummary', tally.ok, tally.warn, tally.fail, tally.down, tally.none);
      return h`<div class="strip-row"><b title="${f.name}">${f.name}</b><div class="strip" role="img" aria-label="${summary}">${spans}</div></div><details class="fold" style="margin:4px 0 10px"><summary><span>${t('CockpitStripShow')} (${f.name})</span></summary><div class="in">${table([{ label: t('CockpitDay') }, { label: t('CockpitStatus') }, { label: t('CockpitChecks') }, { label: t('CockpitRUnreachableRuns'), r: true }], rows)}</div></details>`;
    });
    const stability = h`<div class="card"><h3>${t('CockpitSecStability')}<small>${t('CockpitStabilityHint')}</small></h3><div style="overflow:auto">${strips}</div>${legend([['ok', t('FarmStatusOk')], ['warn', t('FarmStatusWarn')], ['fail', t('FarmStatusAlert')], ['down', t('FarmStatusDown')]])}</div>`;

    const details = farms.map(function (f) {
      const l = latest(f), st = l ? cellState(l.c) : 'down';
      return h`<details class="fold"${f.attention.length && st === 'fail' ? raw(' open') : ''}><summary><span>${f.name} ${badge(st)}</span><span class="muted small">${t('CockpitListed', f.attention.length, f.attentionTotal)}</span></summary><div class="in">${f.attention.length ? table([{ label: t('CockpitItem') }, { label: t('CockpitSection') }, { label: t('CockpitDetail') }, { label: t('CockpitSinceCol') }], f.attention.map(function (a) {
        return h`<tr><td class="wrap-cell"><b>${a.name}</b></td><td>${sectionLabel(a.section)}</td><td class="wrap-cell">${a.detail}</td><td class="num">${sinceText(a)}</td></tr>`;
      })) : h`<div class="empty">${t('CockpitNothingOpen')}</div>`}</div></details>`;
    });
    return h`${causes}<div style="margin-top:16px">${matrix}</div><div style="margin-top:16px">${stability}</div><div class="sec-title">${t('CockpitSecFarmDetail')}</div><div class="grid">${details}</div>`;
  }

  /* ---------- Data quality ---------- */
  function viewQuality() {
    const generated = D.generatedAt ? D.generatedAt.slice(0, 10) : days[N - 1];
    const newestSnap = farms.map(function (f) { return f.latestSnapshot; }).filter(Boolean);
    const stalest = newestSnap.length ? newestSnap.slice().sort()[0] : null;
    const ageDays = stalest ? daysBetween(stalest.slice(0, 10), generated) : null;
    const withData = days.filter(function (d, i) { return snapshotDay(i); }).length;
    const all = collection({ from: 0, to: N });
    const skipped = D.skipped || [];
    const tiles = h`<div class="grid g4">${[
      kpi(ageDays === null ? 'blue' : ageDays <= 1 ? 'ok' : ageDays <= 3 ? 'warn' : 'fail', t('CockpitQFreshness'), ageDays === null ? '\u2014' : dayCount(ageDays), t('CockpitQFreshnessSub'), '', ''),
      kpi('blue', t('CockpitQHistory'), n0(withData), t('CockpitQHistorySub', N), '', ''),
      kpi('blue', t('CockpitQRetention'), D.period && D.period.retentionDays ? dayCount(D.period.retentionDays) : t('CockpitNoLimit'), t('CockpitQRetentionSub', offered.join(', ')), '', ''),
      kpi(skipped.length ? 'warn' : 'ok', t('CockpitQUnreadable'), n0(skipped.length), t('CockpitQUnreadableSub'), '', '')
    ]}</div>`;
    const rows = farms.map(function (f) {
      let withSnap = 0, downDays = 0, snaps = 0;
      f.daily.forEach(function (c) { if (hasData(c)) { withSnap++; snaps += c.snapshots; } if (c && c.unreachable > 0) downDays++; });
      return h`<tr><td><b>${f.name}</b></td><td class="num">${f.latestSnapshot ? stamp(f.latestSnapshot) : '\u2014'}</td><td class="r num">${withSnap}</td><td class="r num">${downDays}</td><td class="r num">${snaps}</td><td class="r num">${f.attention.length} / ${f.attentionTotal}</td></tr>`;
    });
    const perFarm = h`<div class="card"><h3>${t('CockpitQPerFarm')}</h3>${table([{ label: t('FarmLabel') }, { label: t('CockpitQLatest') }, { label: t('CockpitQDaysSnap'), r: true }, { label: t('CockpitQDaysDown'), r: true }, { label: t('CockpitQSnapshots'), r: true }, { label: t('CockpitQListed'), r: true }], rows)}</div>`;
    const notes = [];
    if (all.rate !== null && all.collected < all.expected) notes.push(h`<div class="callout info">${t('CockpitNoteGaps', all.expected - all.collected, all.expected)}</div>`);
    if (farms.some(function (f) { return f.attention.some(function (a) { return a.sinceIsLowerBound; }); })) notes.push(h`<div class="callout info">${t('CockpitNoteLowerBound', dshort(days[0]))}</div>`);
    farms.forEach(function (f) {
      if (f.attentionTruncated) notes.push(h`<div class="callout">${t('CockpitNoteTruncated', f.name, f.attention.length, f.attentionTotal)}</div>`);
      if (f.snapshotsTruncated) notes.push(h`<div class="callout">${t('CockpitNoteSnapshots', f.name)}</div>`);
    });
    if (skipped.length) notes.push(h`<div class="callout">${t('CockpitNoteSkipped')} ${skipped.map(function (s) { return h`<code>${s}</code> `; })}</div>`);
    const exclusions = D.settings && D.settings.current ? D.settings.current.exclusionRules || [] : null;
    notes.push(exclusions === null ? h`<div class="callout info">${t('CockpitNoteNoSettings')}</div>` : exclusions.length ? h`<div class="callout">${t('CockpitNoteExcluded')} ${exclusions.map(function (s) { return h`<code>${s}</code> `; })}</div>` : h`<div class="callout info">${t('CockpitNoteNoExclusion')}</div>`);
    return h`${tiles}<div style="margin-top:16px">${perFarm}</div><div class="grid" style="margin-top:16px">${notes}</div>`;
  }

  /* ---------- Collection tracking ---------- */
  function viewRuns() {
    const r = range(), first = days[r.from];
    const runs = (D.runs || []).filter(function (x) { return x.started.slice(0, 10) >= first; });
    const unreachableDays = [];
    farms.forEach(function (f) { for (let i = r.from; i < r.to; i++) if (f.daily[i] && f.daily[i].unreachable > 0) unreachableDays.push({ farm: f.name, day: days[i], count: f.daily[i].unreachable }); });
    if (!runs.length) return h`${empty(t('CockpitNoRuns'))}${unreachableDays.length ? h`<div style="margin-top:16px">${unreachableNote(unreachableDays)}</div>` : ''}`;
    const complete = runs.filter(function (x) { return x.farms.every(function (f) { return f.outcome === 'ok'; }); }).length;
    const durations = runs.map(function (x) { return x.durationSeconds; });
    const last = runs[runs.length - 1];
    const tiles = h`<div class="grid g4">${[
      kpi('blue', t('CockpitRRuns'), n0(runs.length), t('CockpitRRunsSub', r.len), '', ''),
      kpi(complete === runs.length ? 'ok' : 'warn', t('CockpitRComplete'), pct(complete / runs.length * 100, 1), complete + ' / ' + runs.length, '', ''),
      kpi('blue', t('CockpitRAverage'), minSec(Math.round(average(durations))), '', '', ''),
      kpi('blue', t('CockpitRLast'), minSec(last.durationSeconds), stamp(last.started), '', '')
    ]}</div>`;
    const perDay = [];
    for (let i = r.from; i < r.to; i++) perDay.push(average(runs.filter(function (x) { return x.started.slice(0, 10) === days[i]; }).map(function (x) { return x.durationSeconds; })));
    const chart = h`<div class="card"><h3>${t('CockpitRChart')}</h3>${lineChart(perDay, r.from, function (v) { return minSec(Math.round(v)); }, function (v) { return n1(v / 60) + NO_BREAK + t('CockpitMinutes'); }, t('CockpitRChart'))}</div>`;
    const rows = runs.slice().reverse().slice(0, 50).map(function (x) {
      const dots = x.farms.map(function (f) {
        const st = f.outcome === 'ok' ? cellState({ ok: f.ok, warn: f.warn, fail: f.fail }) : 'down';
        return h`<span title="${f.outcome === 'ok' ? counts(f) : t('FarmStatusDown')}"><span class="dot ${st}"></span>${f.name}</span> `;
      });
      return h`<tr><td class="num">${stamp(x.started)}</td><td class="num">${minSec(x.durationSeconds)}</td><td>${dots}</td><td><span class="badge b-${x.mail === 'sent' ? 'ok' : x.mail === 'failed' ? 'fail' : 'down'}">${hasKey('CockpitMail_' + x.mail) ? t('CockpitMail_' + x.mail) : x.mail}</span></td><td class="num">${x.version}</td></tr>`;
    });
    const list = h`<div class="card" style="margin-top:16px"><h3>${t('CockpitRTable')}${runs.length > 50 ? h`<small>${t('CockpitRecent', 50, runs.length)}</small>` : ''}</h3>${table([{ label: t('CockpitRStart') }, { label: t('CockpitRDuration') }, { label: t('CockpitFarms') }, { label: t('CockpitRMail') }, { label: t('CockpitRVersion') }], rows)}</div>`;
    return h`${tiles}<div style="margin-top:16px">${chart}</div>${list}${unreachableDays.length ? h`<div style="margin-top:16px">${unreachableNote(unreachableDays)}</div>` : ''}`;
  }
  function unreachableNote(list) {
    return h`<div class="callout"><b>${t('CockpitRUnreachable')}</b><ul class="plain">${list.map(function (u) { return h`<li>${u.farm} \u2014 ${dlong(u.day)}${u.count > 1 ? ' (' + u.count + ')' : ''}</li>`; })}</ul></div>`;
  }

  /* ---------- Settings and method ---------- */
  function settingValue(name, v) {
    if (name === 'SQLDiskFreeThresholdPercent') return pct(v, 0);
    if (name === 'EmailMaxItemsPerArea') return n0(v);
    return dayCount(v);
  }
  function viewMethod() {
    const cur = D.settings && D.settings.current, lastRun = (D.runs || []).slice(-1)[0];
    const supplier = (D.runs || []).filter(function (x) { return x.settings; }).pop();
    let current;
    if (!cur) current = h`<div class="callout info">${t('CockpitNoteNoSettings')}</div>`;
    else {
      const names = Object.keys(cur.thresholds || {});
      const rows = names.map(function (name) {
        const th = cur.thresholds[name];
        return h`<tr><td><code>${name}</code></td><td class="num">${settingValue(name, th.value)}</td><td>${th.invalid ? h`<span class="badge b-fail">${t('CockpitInvalid')}</span> ` : ''}<span class="badge ${th.source === 'config' ? 'b-new' : 'b-down'}">${t(th.source === 'config' ? 'CockpitFromConfig' : 'CockpitFromDefault')}</span></td><td>${hasKey('CockpitSetting_' + name) ? t('CockpitSetting_' + name) : ''}</td></tr>`;
      });
      const rules = cur.exclusionRules || [];
      const facts = [
        [t('CockpitConfigFile'), cur.configFile || '\u2014'],
        [t('CockpitExclusions'), rules.length ? rules.join(', ') : t('CockpitNone')]
      ];
      if (lastRun) facts.push([t('CockpitRLast'), t('CockpitLastRunText', lastRun.version, lastRun.language, lastRun.emailMode), true]);
      current = h`<div class="card"><h3>${t('CockpitSecSettings')}<small>${supplier && supplier !== lastRun ? t('CockpitSettingsHintOlder', stamp(supplier.started)) : t('CockpitSettingsHint')}</small></h3>${table([{ label: t('CockpitKey') }, { label: t('CockpitValue') }, { label: t('CockpitOrigin') }, { label: t('CockpitMeaning') }], rows)}<ul class="plain" style="margin-top:12px">${facts.map(function (x) { return h`<li><b>${x[0]}</b> : ${x[2] ? x[1] : h`<code>${x[1]}</code>`}</li>`; })}</ul></div>`;
    }
    const firstDay = days[range().from];
    const changes = (D.settings && D.settings.changes ? D.settings.changes : []).filter(function (c) { return c.started.slice(0, 10) >= firstDay; });
    const changeRows = changes.slice().reverse().map(function (c) {
      const side = function (v, src) { return h`<code>${v === null || v === undefined || v === '' ? '\u2014' : v}</code>${src ? ' (' + t(src === 'config' ? 'CockpitFromConfig' : 'CockpitFromDefault') + ')' : ''}`; };
      return h`<tr><td class="num">${stamp(c.started)}</td><td><code>${c.name}</code></td><td>${side(c.from, c.fromSource)} \u2192 ${side(c.to, c.toSource)}</td></tr>`;
    });
    const changed = h`<div class="card" style="margin-top:16px"><h3>${t('CockpitSecChanges')}</h3>${changes.length ? table([{ label: t('CockpitRStart') }, { label: t('CockpitKey') }, { label: t('CockpitChange') }], changeRows) : h`<div class="empty">${t('CockpitNoChanges')}</div>`}</div>`;
    const bullets = function (keys, args) { return h`<ul class="plain">${keys.map(function (k) { return h`<li>${t.apply(null, [k].concat(args || []))}</li>`; })}</ul>`; };
    const stormy = D.rules && D.rules.weather ? D.rules.weather.stormyAbove : 5;
    const method = h`<div class="sec-title">${t('CockpitSecMethod')}</div><div class="grid g2"><div class="card"><h3>${t('CockpitMethodHealthTitle')}</h3>${bullets(['CockpitMethodHealth1', 'CockpitMethodHealth2', 'CockpitMethodHealth3'])}</div><div class="card"><h3>${t('CockpitMethodWeatherTitle')}</h3>${bullets(['CockpitMethodWeather1', 'CockpitMethodWeather2'], [stormy, t('WeatherSunny'), t('WeatherFair'), t('WeatherCloudy'), t('WeatherStormy')])}</div><div class="card"><h3>${t('CockpitMethodHistoryTitle')}</h3>${bullets(['CockpitMethodHistory1', 'CockpitMethodHistory2', 'CockpitMethodHistory3'])}</div><div class="card"><h3>${t('CockpitMethodLimitsTitle')}</h3>${bullets(['CockpitMethodLimits1', 'CockpitMethodLimits2'])}</div></div>`;
    return h`${current}${changed}${method}`;
  }

  /* ---------- shell ---------- */
  const VIEWS = { direction: viewDirection, it: viewIT, quality: viewQuality, runs: viewRuns, method: viewMethod };
  const TAB_LABEL = { direction: 'CockpitTabDirection', it: 'CockpitTabIT', quality: 'CockpitTabQuality', runs: 'CockpitTabRuns', method: 'CockpitTabMethod' };

  function applyTheme() {
    const dark = state.theme ? state.theme === 'dark' : !!(window.matchMedia && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.setAttribute('data-theme', dark ? 'dark' : 'light');
    document.documentElement.lang = PG.cultures[state.lang].htmlLang || state.lang.slice(0, 2);
    return dark;
  }
  function segment(label, key, items, current) {
    return h`<div class="seg" role="group" aria-label="${label}">${items.map(function (i) { return h`<button type="button" data-set="${key}" data-value="${i[0]}" aria-pressed="${String(i[0] === current)}" title="${i[2] || ''}">${i[1]}</button>`; })}</div>`;
  }
  function header(dark) {
    const latests = farms.map(latest).filter(Boolean);
    const wx = WEATHER[weatherOf(latests.map(function (l) { return weatherKey(l.c); }))];
    const worst = worstOf(farms.map(function (f) { const l = latest(f); const c = f.daily[N - 1]; return c && c.ok === null ? 'down' : l ? cellState(l.c) : 'down'; }));
    const env = D.environment || {};
    const title = 'SPSWeather \u00b7 ' + [env.application, env.name].filter(Boolean).join(' / ');
    const newest = farms.map(function (f) { return f.latestSnapshot; }).filter(Boolean).sort().pop();
    const sub = t(farms.length === 1 ? 'FarmCountOne' : 'FarmCountMany', farms.length) + ' \u00b7 ' + (worst === 'none' ? '' : t(STATUS[worst]) + ' \u00b7 ') + (newest ? t('CockpitAsOfSnapshot', stamp(newest)) : '');
    const controls = [];
    if (offered.length > 1) controls.push(segment(t('CockpitPeriod'), 'p', offered.map(function (p) { return [String(p), dayCount(p)]; }), state.p));
    if (cultures.length > 1) controls.push(segment(t('CockpitLanguage'), 'lang', cultures.map(function (c) { return [c, c.split('-')[0].toUpperCase(), c]; }), state.lang));
    controls.push(segment(t('CockpitTheme'), 'theme', [['light', '\u2600', t('CockpitLight')], ['dark', '\u263e', t('CockpitDark')]], dark ? 'dark' : 'light'));
    const tabs = TABS.map(function (id) {
      return h`<button type="button" role="tab" id="tab-${id}" data-tab="${id}" aria-selected="${String(id === state.tab)}" tabindex="${id === state.tab ? 0 : -1}">${t(TAB_LABEL[id])}${id === 'direction' && farms.length ? h`<span class="cnt">${farms.reduce(function (s, f) { return s + f.attentionTotal; }, 0)}</span>` : ''}</button>`;
    });
    return h`<div class="hdr-top"><div class="brand"><div class="ico">${wx[0]}</div><div><h1>${title}</h1><small>${sub}</small></div></div><div class="ctrls">${controls}</div></div><div class="tabs" role="tablist">${tabs}</div>`;
  }
  function footer() {
    const generated = D.generatedAt ? stamp(D.generatedAt) : '';
    return h`<div>SPSWeather ${PG.version} \u00b7 ${t('CockpitSchema')} ${D.schemaVersion} \u00b7 ${t('Generated')} ${generated}</div><div>${t('CockpitReadOnly')}</div>`;
  }
  function render(focus) {
    const dark = applyTheme();
    document.title = 'SPSWeather \u00b7 ' + [(D.environment || {}).application, (D.environment || {}).name].filter(Boolean).join(' / ');
    document.getElementById('spsw-header').innerHTML = header(dark).s;
    document.getElementById('spsw-main').innerHTML = h`<div role="tabpanel" aria-labelledby="tab-${state.tab}">${VIEWS[state.tab]()}</div>`.s;
    document.getElementById('spsw-footer').innerHTML = footer().s;
    if (focus) { const el = document.querySelector(focus); if (el) el.focus(); }
  }
  function set(key, value, focus) {
    state[key] = value;
    writeHash();
    render(focus);
  }
  function start() {
    readHash();
    document.addEventListener('click', function (e) {
      const target = e.target.closest ? e.target.closest('[data-set],[data-tab],[data-scroll]') : null;
      if (!target) return;
      e.preventDefault();
      if (target.dataset.scroll) {
        const el = document.getElementById(target.dataset.scroll);
        if (el) el.scrollIntoView({ behavior: 'smooth', block: 'start' });
      } else if (target.dataset.tab) {
        set('tab', target.dataset.tab, '#tab-' + target.dataset.tab);
        window.scrollTo(0, 0);
      } else if (VALID[target.dataset.set] && VALID[target.dataset.set](target.dataset.value)) {
        set(target.dataset.set, target.dataset.value, '[data-set="' + target.dataset.set + '"][aria-pressed="true"]');
      }
    });
    document.addEventListener('keydown', function (e) {
      if (e.key !== 'ArrowLeft' && e.key !== 'ArrowRight') return;
      const tab = e.target.closest ? e.target.closest('[role="tab"]') : null;
      if (!tab) return;
      const i = TABS.indexOf(tab.dataset.tab), next = TABS[(i + (e.key === 'ArrowRight' ? 1 : TABS.length - 1)) % TABS.length];
      e.preventDefault();
      set('tab', next, '#tab-' + next);
    });
    let narrow = window.innerWidth < 700;
    window.addEventListener('resize', function () { if ((window.innerWidth < 700) !== narrow) { narrow = !narrow; render(); } });
    window.addEventListener('hashchange', function () { readHash(); render(); });
    render();
  }
  try { start(); } catch (e) { fail(e && e.message ? e.message : String(e)); }
})();
