"use strict";

/* 自治体生成AIレーダー app.js
 * CSVを読み込み、件数集計・一覧・検索・詳細表示を動的に生成する。
 * 外部ライブラリは使用しない。
 */

var CASES_CSV_PATH = "data/validation/cases.csv";
var EVENTS_CSV_PATH = "data/validation/events.csv";

var KEYWORD_FIELDS = [
  "case_id", "case_title", "municipality", "prefecture",
  "companies", "product_name", "genai_model", "use_case", "notes"
];

var allCases = [];
var allEvents = [];
var previousActiveElement = null;

document.addEventListener("DOMContentLoaded", function () {
  setupModalStatic();
  setupFilterFormStatic();
  loadData();
});

/* ---------- データ読み込み ---------- */

function loadData() {
  Promise.all([fetchText(CASES_CSV_PATH), fetchText(EVENTS_CSV_PATH)])
    .then(function (texts) {
      allCases = parseCsvToObjects(texts[0]);
      allEvents = parseCsvToObjects(texts[1]);

      var statusEl = document.getElementById("load-status");
      statusEl.hidden = true;
      document.getElementById("summary-grid").hidden = false;

      renderSummary();
      renderStatusDistribution();
      renderCategoryDistribution();
      populateFilterOptions();
      applyFilters();
      renderHighlights();
    })
    .catch(function (err) {
      console.error(err);
      showLoadError();
    });
}

function fetchText(path) {
  return fetch(path).then(function (res) {
    if (!res.ok) {
      throw new Error("fetch failed: " + path);
    }
    return res.text();
  });
}

function showLoadError() {
  var el = document.getElementById("load-status");
  el.textContent = "データの読み込みに失敗しました。\nGitHub PagesまたはWebサーバー経由で開いてください。";
  el.classList.add("is-error");
  el.hidden = false;
  document.getElementById("summary-grid").hidden = true;
}

/* ---------- CSVパーサー（RFC4180準拠・引用符/カンマ/改行対応） ---------- */

function parseCsv(text) {
  var rows = [];
  var row = [];
  var field = "";
  var inQuotes = false;

  for (var i = 0; i < text.length; i++) {
    var ch = text[i];

    if (inQuotes) {
      if (ch === '"') {
        if (text[i + 1] === '"') {
          field += '"';
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field += ch;
      }
      continue;
    }

    if (ch === '"') {
      inQuotes = true;
    } else if (ch === ",") {
      row.push(field);
      field = "";
    } else if (ch === "\r") {
      if (text[i + 1] !== "\n") {
        row.push(field);
        field = "";
        rows.push(row);
        row = [];
      }
    } else if (ch === "\n") {
      row.push(field);
      field = "";
      rows.push(row);
      row = [];
    } else {
      field += ch;
    }
  }

  if (field.length > 0 || row.length > 0) {
    row.push(field);
    rows.push(row);
  }

  return rows;
}

function parseCsvToObjects(text) {
  var clean = text.replace(/^﻿/, "");
  var rows = parseCsv(clean).filter(function (r) {
    return !(r.length === 1 && r[0] === "");
  });
  if (rows.length === 0) {
    return [];
  }
  var header = rows[0];
  return rows.slice(1).map(function (r) {
    var obj = {};
    header.forEach(function (h, idx) {
      obj[h] = r[idx] !== undefined ? r[idx] : "";
    });
    return obj;
  });
}

/* ---------- 表示ヘルパー ---------- */

function esc(value) {
  var str = value === undefined || value === null ? "" : String(value);
  return str.replace(/[&<>"']/g, function (ch) {
    return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[ch];
  });
}

function isUnknown(v) {
  return v === undefined || v === null || v === "" || v === "unknown";
}

function displayValueList(v) {
  return isUnknown(v) ? "未確認" : v;
}

function displayValueDetail(v) {
  return isUnknown(v) ? "本データベースでは未確認" : v;
}

function displayBoolean(v) {
  if (v === "true") return "確認済み";
  if (v === "false") return "該当しないことを確認";
  return "未確認";
}

function humanizeList(v) {
  if (isUnknown(v)) return v;
  return v
    .split(";")
    .map(function (s) { return s.trim(); })
    .filter(Boolean)
    .join("、");
}

function formatYen(v) {
  if (isUnknown(v)) return "本データベースでは未確認";
  var num = Number(v);
  if (Number.isNaN(num)) return v;
  return num.toLocaleString("ja-JP") + "円";
}

function formatCount(v, suffix) {
  if (isUnknown(v)) return "本データベースでは未確認";
  var num = Number(v);
  if (Number.isNaN(num)) return v;
  return num.toLocaleString("ja-JP") + suffix;
}

function statusBadgeClass(status) {
  switch (status) {
    case "本導入": return "status-adopted";
    case "契約・採択": return "status-contracted";
    case "続報未確認": return "status-followup";
    case "共同利用": return "status-shared";
    case "実証結果公表":
    case "効果検証":
      return "status-pilot";
    default: return "";
  }
}

function statusBadgeHtml(status) {
  var label = isUnknown(status) ? "未確認" : status;
  var cls = statusBadgeClass(status);
  return '<span class="status-badge ' + cls + '">' + esc(label) + "</span>";
}

function setText(id, text) {
  var el = document.getElementById(id);
  if (el) el.textContent = text;
}

/* ---------- 集計 ---------- */

function countBy(list, key) {
  var map = {};
  var order = [];
  list.forEach(function (item) {
    var val = item[key];
    if (!(val in map)) {
      map[val] = 0;
      order.push(val);
    }
    map[val]++;
  });
  return order
    .map(function (value) { return { value: value, count: map[value] }; })
    .sort(function (a, b) {
      if (b.count !== a.count) return b.count - a.count;
      return String(a.value).localeCompare(String(b.value), "ja");
    });
}

function renderSummary() {
  var total = allCases.length;
  var adopted = allCases.filter(function (c) { return c.current_status === "本導入"; }).length;
  var unconfirmed = allCases.filter(function (c) { return c.current_status === "続報未確認"; }).length;

  setText("summary-case-count", total + "件");
  setText("summary-event-count", allEvents.length + "件");
  setText("summary-adopted-count", adopted + "件");
  setText("summary-unconfirmed-count", unconfirmed + "件");
}

function renderBarList(containerId, distribution, total) {
  var container = document.getElementById(containerId);
  container.innerHTML = distribution.map(function (item) {
    var label = displayValueList(item.value);
    var pct = total > 0 ? (item.count / total) * 100 : 0;
    var pctText = pct.toFixed(1) + "%";
    return (
      '<div class="bar-row">' +
      '<div class="bar-row-label">' + esc(label) + "</div>" +
      '<div class="bar-track"><div class="bar-fill" style="width:' + pct.toFixed(2) + '%"></div></div>' +
      '<div class="bar-row-value"><strong>' + item.count + "件</strong>（初期収録案件に占める割合：" + pctText + "）</div>" +
      "</div>"
    );
  }).join("");
}

function renderStatusDistribution() {
  var dist = countBy(allCases, "current_status");
  renderBarList("status-distribution", dist, allCases.length);
}

function renderCategoryDistribution() {
  var dist = countBy(allCases, "primary_category");
  renderBarList("category-distribution", dist, allCases.length);
}

/* ---------- 検索・絞り込み ---------- */

function uniqueValues(list, key) {
  var set = {};
  var out = [];
  list.forEach(function (item) {
    var v = item[key];
    if (v && !(v in set)) {
      set[v] = true;
      out.push(v);
    }
  });
  return out.sort(function (a, b) { return a.localeCompare(b, "ja"); });
}

function populateFilterOptions() {
  fillSelect("filter-prefecture", uniqueValues(allCases, "prefecture"));
  fillSelect("filter-status", uniqueValues(allCases, "current_status"));
  fillSelect("filter-category", uniqueValues(allCases, "primary_category"));
  fillSelect("filter-result-type", uniqueValues(allCases, "quantitative_result_type"));
}

function fillSelect(id, values) {
  var select = document.getElementById(id);
  values.forEach(function (v) {
    var opt = document.createElement("option");
    opt.value = v;
    opt.textContent = displayValueList(v);
    select.appendChild(opt);
  });
}

function setupFilterFormStatic() {
  var form = document.getElementById("filter-form");
  document.getElementById("filter-keyword").addEventListener("input", applyFilters);
  document.getElementById("filter-prefecture").addEventListener("change", applyFilters);
  document.getElementById("filter-status").addEventListener("change", applyFilters);
  document.getElementById("filter-category").addEventListener("change", applyFilters);
  document.getElementById("filter-result-type").addEventListener("change", applyFilters);
  form.addEventListener("submit", function (e) { e.preventDefault(); });
  form.addEventListener("reset", function () {
    setTimeout(applyFilters, 0);
  });
}

function getFilteredCases() {
  var keyword = document.getElementById("filter-keyword").value.trim().toLowerCase();
  var prefecture = document.getElementById("filter-prefecture").value;
  var status = document.getElementById("filter-status").value;
  var category = document.getElementById("filter-category").value;
  var resultType = document.getElementById("filter-result-type").value;

  return allCases.filter(function (c) {
    if (prefecture && c.prefecture !== prefecture) return false;
    if (status && c.current_status !== status) return false;
    if (category && c.primary_category !== category) return false;
    if (resultType && c.quantitative_result_type !== resultType) return false;
    if (keyword) {
      var haystack = KEYWORD_FIELDS.map(function (f) { return c[f] || ""; }).join(" ").toLowerCase();
      if (haystack.indexOf(keyword) === -1) return false;
    }
    return true;
  }).sort(function (a, b) { return a.case_id.localeCompare(b.case_id); });
}

function applyFilters() {
  if (!allCases.length) return;
  var filtered = getFilteredCases();
  renderCaseList(filtered);
  setText("result-count", "検索結果：" + filtered.length + "件");
}

/* ---------- 案件一覧 ---------- */

function renderCaseList(list) {
  var tbody = document.getElementById("case-table-body");
  var cards = document.getElementById("case-cards");
  tbody.innerHTML = list.map(caseRowHtml).join("");
  cards.innerHTML = list.map(caseCardHtml).join("");
}

function caseRowHtml(c) {
  return (
    "<tr>" +
    "<td>" + esc(c.case_id) + "</td>" +
    "<td>" + esc(c.municipality) + "</td>" +
    "<td>" + esc(c.prefecture) + "</td>" +
    "<td>" + esc(c.case_title) + "</td>" +
    "<td>" + statusBadgeHtml(c.current_status) + "</td>" +
    "<td>" + esc(displayValueList(c.primary_category)) + "</td>" +
    "<td>" + esc(displayValueList(humanizeList(c.companies))) + "</td>" +
    "<td>" + esc(displayValueList(c.product_name)) + "</td>" +
    "<td>" + esc(displayValueList(c.quantitative_result_type)) + "</td>" +
    "<td>" + esc(displayValueList(c.last_checked)) + "</td>" +
    '<td><button type="button" class="detail-btn" data-case-id="' + esc(c.case_id) + '">詳細を見る</button></td>' +
    "</tr>"
  );
}

function caseCardHtml(c) {
  function row(label, value) {
    return (
      '<div class="case-card-row">' +
      '<span class="case-card-label">' + esc(label) + "</span>" +
      "<span>" + value + "</span>" +
      "</div>"
    );
  }
  return (
    '<div class="case-card">' +
    '<p class="case-card-id">' + esc(c.case_id) + "</p>" +
    '<p class="case-card-title">' + esc(c.case_title) + "</p>" +
    row("自治体", esc(c.municipality) + "（" + esc(c.prefecture) + "）") +
    row("現在ステータス", statusBadgeHtml(c.current_status)) +
    row("主要カテゴリ", esc(displayValueList(c.primary_category))) +
    row("企業", esc(displayValueList(humanizeList(c.companies)))) +
    row("製品名", esc(displayValueList(c.product_name))) +
    row("定量結果タイプ", esc(displayValueList(c.quantitative_result_type))) +
    row("最終確認日", esc(displayValueList(c.last_checked))) +
    '<div class="case-card-actions"><button type="button" class="detail-btn" data-case-id="' + esc(c.case_id) + '">詳細を見る</button></div>' +
    "</div>"
  );
}

/* ---------- 注目案件 ---------- */

function renderHighlights() {
  var countMap = {};
  allEvents.forEach(function (e) {
    countMap[e.case_id] = (countMap[e.case_id] || 0) + 1;
  });

  var entries = Object.keys(countMap).map(function (caseId) {
    return { caseId: caseId, count: countMap[caseId] };
  }).sort(function (a, b) {
    if (b.count !== a.count) return b.count - a.count;
    return a.caseId.localeCompare(b.caseId);
  }).slice(0, 6);

  var container = document.getElementById("highlight-grid");
  container.innerHTML = entries.map(function (entry) {
    var c = allCases.filter(function (x) { return x.case_id === entry.caseId; })[0];
    if (!c) return "";
    return (
      '<div class="highlight-card">' +
      '<p class="highlight-card-id">' + esc(c.case_id) + "／" + esc(c.municipality) + "</p>" +
      '<h3 class="highlight-card-title">' + esc(c.case_title) + "</h3>" +
      '<div class="highlight-card-meta">' +
      "<span>登録イベント数：<strong>" + entry.count + "件</strong></span>" +
      statusBadgeHtml(c.current_status) +
      "</div>" +
      '<button type="button" class="btn btn-outline detail-btn" data-case-id="' + esc(c.case_id) + '">案件詳細を開く</button>' +
      "</div>"
    );
  }).join("");
}

/* ---------- 案件詳細モーダル ---------- */

function setupModalStatic() {
  document.body.addEventListener("click", function (e) {
    var btn = e.target.closest(".detail-btn");
    if (btn) {
      openCaseDetail(btn.getAttribute("data-case-id"));
    }
  });

  document.getElementById("modal-close").addEventListener("click", closeModal);

  document.getElementById("modal-overlay").addEventListener("click", function (e) {
    if (e.target.id === "modal-overlay") closeModal();
  });

  document.addEventListener("keydown", function (e) {
    if (e.key === "Escape") {
      var overlay = document.getElementById("modal-overlay");
      if (!overlay.hidden) closeModal();
    }
  });
}

function openCaseDetail(caseId) {
  var c = allCases.filter(function (x) { return x.case_id === caseId; })[0];
  if (!c) return;

  previousActiveElement = document.activeElement;
  document.getElementById("modal-content").innerHTML = buildDetailHtml(c);

  var overlay = document.getElementById("modal-overlay");
  overlay.hidden = false;
  document.body.style.overflow = "hidden";
  document.getElementById("modal-close").focus();
}

function closeModal() {
  var overlay = document.getElementById("modal-overlay");
  overlay.hidden = true;
  document.body.style.overflow = "";
  if (previousActiveElement && typeof previousActiveElement.focus === "function") {
    previousActiveElement.focus();
  }
}

function buildSourceLinks(c) {
  var links = [];
  if (!isUnknown(c.source_url_1)) {
    links.push({ url: c.source_url_1, type: isUnknown(c.source_type_1) ? "出典" : c.source_type_1 });
  }
  if (!isUnknown(c.source_url_2)) {
    links.push({ url: c.source_url_2, type: isUnknown(c.source_type_2) ? "出典" : c.source_type_2 });
  }
  return links;
}

function sortEvents(events) {
  var withDate = events.filter(function (e) { return !isUnknown(e.event_date); })
    .sort(function (a, b) { return a.event_date.localeCompare(b.event_date); });
  var withoutDate = events.filter(function (e) { return isUnknown(e.event_date); });
  return withDate.concat(withoutDate);
}

function eventItemHtml(e) {
  var dateLabel = isUnknown(e.event_date) ? "未確認" : e.event_date;
  var orgLabel = displayValueDetail(humanizeList(e.organization));
  var sourceHtml = !isUnknown(e.source_url)
    ? '<a href="' + esc(e.source_url) + '" target="_blank" rel="noopener noreferrer">' +
      esc(isUnknown(e.source_type) ? "出典" : e.source_type) + "（外部サイトを開く）</a>"
    : "本データベースでは未確認";

  return (
    '<li class="timeline-item">' +
    '<p class="timeline-date">' + esc(dateLabel) + '<span class="timeline-type">' + esc(e.event_type) + "</span></p>" +
    '<p class="timeline-title">' + esc(e.event_title) + "</p>" +
    '<p class="timeline-summary">' + esc(e.event_summary) + "</p>" +
    '<p class="timeline-org">' + esc(orgLabel) + " ／ " + sourceHtml + "</p>" +
    "</li>"
  );
}

function buildDetailHtml(c) {
  var events = allEvents.filter(function (e) { return e.case_id === c.case_id; });
  var sortedEvents = sortEvents(events);
  var sourceLinks = buildSourceLinks(c);

  var grid =
    '<dl class="detail-grid">' +
    "<dt>自治体</dt><dd>" + esc(displayValueDetail(c.municipality)) + "</dd>" +
    "<dt>担当部署</dt><dd>" + esc(displayValueDetail(c.department)) + "</dd>" +
    "<dt>企業</dt><dd>" + esc(displayValueDetail(humanizeList(c.companies))) + "</dd>" +
    "<dt>製品名</dt><dd>" + esc(displayValueDetail(c.product_name)) + "</dd>" +
    "<dt>生成AIモデル</dt><dd>" + esc(displayValueDetail(c.genai_model)) + "</dd>" +
    "<dt>ユースケース</dt><dd>" + esc(displayValueDetail(humanizeList(c.use_case))) + "</dd>" +
    "<dt>主要カテゴリ</dt><dd>" + esc(displayValueDetail(c.primary_category)) + "</dd>" +
    "<dt>発表日</dt><dd>" + esc(displayValueDetail(c.announcement_date)) + "</dd>" +
    "<dt>開始日</dt><dd>" + esc(displayValueDetail(c.start_date)) + "</dd>" +
    "<dt>終了日</dt><dd>" + esc(displayValueDetail(c.end_date)) + "</dd>" +
    "<dt>現在ステータス</dt><dd>" + statusBadgeHtml(c.current_status) + "</dd>" +
    "<dt>利用人数</dt><dd>" + esc(formatCount(c.users_count, "人")) + "</dd>" +
    "<dt>契約金額</dt><dd>" + esc(formatYen(c.contract_amount_yen)) + "</dd>" +
    "<dt>調達方法</dt><dd>" + esc(displayValueDetail(c.procurement_method)) + "</dd>" +
    "<dt>定量結果</dt><dd>" + esc(displayValueDetail(c.quantitative_result)) + "</dd>" +
    "<dt>定量結果タイプ</dt><dd>" + esc(displayValueDetail(c.quantitative_result_type)) + "</dd>" +
    "<dt>本導入フラグ</dt><dd>" + esc(displayBoolean(c.commercialized)) + "</dd>" +
    "<dt>共同利用フラグ</dt><dd>" + esc(displayBoolean(c.shared_use)) + "</dd>" +
    "<dt>他自治体展開フラグ</dt><dd>" + esc(displayBoolean(c.expanded_to_other_municipalities)) + "</dd>" +
    "<dt>備考</dt><dd>" + esc(displayValueDetail(c.notes)) + "</dd>" +
    "<dt>最終確認日</dt><dd>" + esc(displayValueDetail(c.last_checked)) + "</dd>" +
    "</dl>";

  var sourceSection =
    '<h4 class="detail-section-title">参照元</h4>' +
    (sourceLinks.length
      ? '<ul class="source-links">' + sourceLinks.map(function (l) {
          return '<li><a href="' + esc(l.url) + '" target="_blank" rel="noopener noreferrer">' +
            esc(l.type) + "（外部サイトを開く）</a></li>";
        }).join("") + "</ul>"
      : '<p class="timeline-empty">参照元リンクは登録されていません。</p>');

  var timelineSection =
    '<h4 class="detail-section-title">案件タイムライン</h4>' +
    (sortedEvents.length
      ? '<ul class="timeline-list">' + sortedEvents.map(eventItemHtml).join("") + "</ul>"
      : '<p class="timeline-empty">この案件の時系列イベントは現在未登録です。</p>');

  return (
    '<h3 id="modal-title" class="detail-title">' + esc(c.case_title) + "</h3>" +
    '<p class="detail-id">' + esc(c.case_id) + "</p>" +
    grid +
    sourceSection +
    timelineSection
  );
}
