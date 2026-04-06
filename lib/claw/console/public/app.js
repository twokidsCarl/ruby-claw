// Claw Console — Client-side application
(function() {
  "use strict";

  // --- Utilities ---

  function api(method, path, body) {
    var opts = { method: method, headers: {} };
    if (body) {
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    return fetch(path, opts).then(function(r) { return r.json(); });
  }

  function esc(str) {
    var d = document.createElement("div");
    d.textContent = str;
    return d.innerHTML;
  }

  function timeStr(iso) {
    if (!iso) return "—";
    var d = new Date(iso);
    return d.toLocaleTimeString();
  }

  // --- Highlight active nav ---

  var path = window.location.pathname;
  document.querySelectorAll(".nav-link").forEach(function(a) {
    if (a.getAttribute("href") === path) a.classList.add("active");
  });

  // --- Dashboard ---

  var statVersion = document.getElementById("stat-version");
  if (statVersion) {
    api("GET", "/api/status").then(function(d) {
      document.getElementById("stat-version").textContent = "v" + d.version;
      document.getElementById("stat-tools").textContent = d.tool_count;
      document.getElementById("stat-memories").textContent = d.memory_count;
      document.getElementById("stat-snapshots").textContent = d.snapshot_count;
      document.getElementById("stat-events").textContent = d.event_count;
    });
  }

  // --- Header status ---

  var headerStatus = document.getElementById("header-status");
  if (headerStatus) {
    api("GET", "/api/status").then(function(d) {
      headerStatus.textContent = "v" + d.version;
    });
  }

  // --- Prompt Inspector ---

  var promptArea = document.getElementById("prompt-template");
  if (promptArea) {
    api("GET", "/api/prompt").then(function(d) {
      promptArea.value = d.template || "";
      var container = document.getElementById("prompt-sections");
      if (d.sections && d.sections.length) {
        container.innerHTML = d.sections.map(function(s) {
          return '<div class="section-item">' + esc(s) + '</div>';
        }).join("");
      } else {
        container.innerHTML = '<p class="muted">No dynamic sections.</p>';
      }
    });
  }

  window.savePrompt = function() {
    var content = document.getElementById("prompt-template").value;
    api("POST", "/api/prompt", { content: content }).then(function() {
      document.getElementById("prompt-status").textContent = "Saved!";
      setTimeout(function() {
        document.getElementById("prompt-status").textContent = "";
      }, 2000);
    });
  };

  // --- Monitor (SSE) ---

  var eventStream = document.getElementById("event-stream");
  if (eventStream) {
    var eventCount = 0;
    var source = new EventSource("/api/events");

    source.onmessage = function(e) {
      var evt = JSON.parse(e.data);
      var filterEl = document.getElementById("event-filter");
      var filter = filterEl ? filterEl.value : "";
      if (filter && !evt.type.startsWith(filter)) return;

      eventCount++;
      var countEl = document.getElementById("event-count");
      if (countEl) countEl.textContent = eventCount + " events";

      if (eventCount === 1) eventStream.innerHTML = "";

      var div = document.createElement("div");
      div.className = "event-item";
      div.innerHTML =
        '<span class="event-time">' + timeStr(evt.timestamp) + '</span>' +
        '<span class="event-type ' + esc(evt.type) + '">' + esc(evt.type) + '</span>' +
        '<span class="event-data">' + esc(JSON.stringify(evt.data || {})) + '</span>';
      eventStream.appendChild(div);

      var autoScroll = document.getElementById("auto-scroll");
      if (autoScroll && autoScroll.checked) {
        eventStream.scrollTop = eventStream.scrollHeight;
      }
    };

    source.onerror = function() {
      if (eventCount === 0) {
        eventStream.innerHTML = '<p class="muted">Event stream disconnected. Retrying...</p>';
      }
    };
  }

  // --- Traces ---

  var traceList = document.getElementById("trace-list");
  if (traceList) {
    api("GET", "/api/traces").then(function(traces) {
      if (!traces.length) {
        traceList.innerHTML = '<p class="muted" style="padding:0.75rem">No traces found.</p>';
        return;
      }
      traceList.innerHTML = traces.map(function(t) {
        return '<div class="trace-entry" data-id="' + esc(t.id) + '">' +
          '<div class="trace-entry-id">' + esc(t.id) + '</div>' +
          '<div class="trace-entry-meta">' + esc(t.modified) + '</div>' +
          '</div>';
      }).join("");

      traceList.querySelectorAll(".trace-entry").forEach(function(el) {
        el.addEventListener("click", function() {
          traceList.querySelectorAll(".trace-entry").forEach(function(e) { e.classList.remove("active"); });
          el.classList.add("active");
          loadTrace(el.dataset.id);
        });
      });
    });
  }

  function loadTrace(id) {
    var detail = document.getElementById("trace-detail");
    detail.innerHTML = '<p class="muted">Loading...</p>';
    api("GET", "/api/traces/" + encodeURIComponent(id)).then(function(d) {
      detail.textContent = d.content || "Empty trace.";
    });
  }

  // --- Memory ---

  var memoryBody = document.getElementById("memory-body");
  if (memoryBody) {
    loadMemories();
  }

  function loadMemories() {
    api("GET", "/api/memory").then(function(mems) {
      var body = document.getElementById("memory-body");
      if (!mems || !mems.length) {
        body.innerHTML = '<tr><td colspan="4" class="muted">No memories stored.</td></tr>';
        return;
      }
      body.innerHTML = mems.map(function(m) {
        return '<tr>' +
          '<td>' + esc(String(m.id)) + '</td>' +
          '<td>' + esc(m.content) + '</td>' +
          '<td>' + esc(m.created_at || "—") + '</td>' +
          '<td><button class="btn btn-sm btn-danger" onclick="forgetMemory(' + m.id + ')">Forget</button></td>' +
          '</tr>';
      }).join("");
    });
  }

  window.addMemory = function() {
    var input = document.getElementById("memory-input");
    var content = input.value.trim();
    if (!content) return;
    api("POST", "/api/memory", { content: content }).then(function() {
      input.value = "";
      loadMemories();
    });
  };

  window.forgetMemory = function(id) {
    api("DELETE", "/api/memory/" + id).then(function() { loadMemories(); });
  };

  // --- Tools ---

  var coreTools = document.getElementById("core-tools");
  if (coreTools) {
    api("GET", "/api/tools").then(function(d) {
      coreTools.innerHTML = (d.core || []).map(function(t) {
        return '<div class="tool-card"><div><div class="tool-name">' + esc(t.name) + '</div>' +
          '<div class="tool-desc">' + esc(t.description || "") + '</div></div>' +
          '<span class="tool-badge loaded">core</span></div>';
      }).join("") || '<p class="muted">No core tools.</p>';

      var projectTools = document.getElementById("project-tools");
      projectTools.innerHTML = (d.project || []).map(function(t) {
        var badge = t.loaded
          ? '<span class="tool-badge loaded">loaded</span>'
          : '<button class="btn btn-sm" onclick="loadTool(\'' + esc(t.name) + '\')">Load</button>';
        return '<div class="tool-card"><div><div class="tool-name">' + esc(t.name) + '</div>' +
          '<div class="tool-desc">' + esc(t.description || "") + '</div></div>' + badge + '</div>';
      }).join("") || '<p class="muted">No project tools. Create tools in .ruby-claw/tools/</p>';
    });
  }

  window.loadTool = function(name) {
    api("POST", "/api/tools/load", { name: name }).then(function() {
      window.location.reload();
    });
  };

  // --- Snapshots ---

  var snapshotBody = document.getElementById("snapshot-body");
  if (snapshotBody) {
    loadSnapshots();
  }

  function loadSnapshots() {
    api("GET", "/api/snapshots").then(function(snaps) {
      var body = document.getElementById("snapshot-body");
      if (!snaps || !snaps.length) {
        body.innerHTML = '<tr><td colspan="4" class="muted">No snapshots.</td></tr>';
        return;
      }
      body.innerHTML = snaps.map(function(s) {
        return '<tr>' +
          '<td>#' + esc(String(s.id)) + '</td>' +
          '<td>' + esc(s.label || "(unlabeled)") + '</td>' +
          '<td>' + esc(s.timestamp || "—") + '</td>' +
          '<td><button class="btn btn-sm btn-secondary" onclick="rollbackSnapshot(' + s.id + ')">Rollback</button></td>' +
          '</tr>';
      }).join("");
    });
  }

  window.createSnapshot = function() {
    api("POST", "/api/snapshots").then(function() { loadSnapshots(); });
  };

  window.rollbackSnapshot = function(id) {
    if (!confirm("Rollback to snapshot #" + id + "?")) return;
    api("POST", "/api/snapshots/" + id + "/rollback").then(function() { loadSnapshots(); });
  };

  // --- Experiments (placeholder) ---

  window.newExperiment = function() {
    alert("Experiment platform coming in Sprint 15.");
  };
})();
