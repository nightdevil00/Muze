// Dock model helpers for Muze (inspired by Omarchy's dock).

var POSITIONS = ["top", "bottom", "left", "right"];

function normalizePosition(value) {
  var position = String(value || "").trim().toLowerCase();
  return POSITIONS.indexOf(position) >= 0 ? position : "bottom";
}

function isVertical(position) {
  var p = normalizePosition(position);
  return p === "left" || p === "right";
}

function normalizeId(value) {
  var id = String(value || "").trim();
  if (id.slice(-8) === ".desktop") id = id.slice(0, -8);
  return id;
}

function pinnedIds(dockConfig) {
  var source = dockConfig && Array.isArray(dockConfig.pinned) ? dockConfig.pinned : [];
  var ids = [];
  for (var i = 0; i < source.length; i++) {
    var id = normalizeId(source[i]);
    if (id && ids.indexOf(id) === -1) ids.push(id);
  }
  return ids;
}

function isDockWindow(window) {
  if (!window || !window.key) return false;
  if (window.minimized === true) return true;
  return window.hasEntry === true && window.workspaceId >= 0;
}

function buildItems(pinned, windows) {
  var items = [];
  var byKey = {};

  function itemFor(key, isPinned) {
    if (!byKey[key]) {
      byKey[key] = { key: key, pinned: isPinned, windows: [] };
      items.push(byKey[key]);
    }
    return byKey[key];
  }

  for (var i = 0; i < (pinned || []).length; i++) {
    if (pinned[i]) itemFor(pinned[i], true);
  }

  for (var j = 0; j < (windows || []).length; j++) {
    var w = windows[j];
    if (isDockWindow(w)) itemFor(w.key, false).windows.push(w);
  }

  return items;
}

function orderItems(items, order) {
  var byKey = {};
  for (var i = 0; i < (items || []).length; i++) byKey[items[i].key] = items[i];
  var result = [];
  var placed = {};
  for (var j = 0; j < (order || []).length; j++) {
    var key = order[j];
    if (byKey[key] && !placed[key]) {
      result.push(byKey[key]);
      placed[key] = true;
    }
  }
  for (var k = 0; k < (items || []).length; k++) {
    if (!placed[items[k].key]) result.push(items[k]);
  }
  return result;
}

function orderWithKeyAt(order, key, index) {
  var keys = (order || []).filter(function(other) { return other !== key; });
  keys.splice(Math.max(0, Math.min(keys.length, index)), 0, key);
  return keys;
}

function pinsInOrder(order, pinned, allPinned) {
  var result = (order || []).filter(function(key) { return pinned[key] === true; });
  for (var i = 0; i < (allPinned || []).length; i++) {
    if (result.indexOf(allPinned[i]) === -1 && (order || []).indexOf(allPinned[i]) === -1)
      result.push(allPinned[i]);
  }
  return result;
}

function pickWindow(windows, workspaceId) {
  var list = windows || [];
  if (list.length === 0) return -1;
  function rank(w) {
    if (w.minimized) return 1;
    return w.workspaceId === workspaceId ? 0 : 2;
  }
  var order = list.map(function(w, i) { return i; });
  order.sort(function(a, b) { return rank(list[a]) - rank(list[b]) || a - b; });
  for (var i = 0; i < order.length; i++) {
    if (list[order[i]].activated) return order[(i + 1) % order.length];
  }
  return order[0];
}
