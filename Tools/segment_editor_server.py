#!/usr/bin/env python3
import argparse
import json
import mimetypes
import subprocess
import urllib.parse
import webbrowser
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
PLAN_PATH = ROOT / "Samples" / "hajimi-local" / "segment-plan.json"
RAW_DIR = ROOT / "Samples" / "hajimi-local" / "raw"
CLIPS_DIR = ROOT / "Samples" / "hajimi-local" / "clips"
RECUT_SCRIPT = ROOT / "Tools" / "recut_hajimi_segments.py"


INDEX_HTML = r"""<!doctype html>
<html lang="zh-CN">
<head>
  <meta charset="utf-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1" />
  <title>Hajimi Segment Editor</title>
  <style>
    :root { color-scheme: dark; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0; background: #111318; color: #eef0f4; }
    header { display: flex; align-items: center; gap: 12px; padding: 14px 18px; border-bottom: 1px solid #2a2e38; background: #171a21; position: sticky; top: 0; z-index: 2; }
    header h1 { font-size: 16px; margin: 0; }
    button { border: 1px solid #3a4050; background: #232938; color: #f5f6fa; border-radius: 8px; padding: 8px 10px; cursor: pointer; }
    button:hover { background: #2d3548; }
    button.primary { background: #3f66d4; border-color: #5578dd; }
    button.warn { background: #5a3a20; border-color: #9b6b33; }
    main { display: grid; grid-template-columns: 330px 1fr; height: calc(100vh - 59px); }
    aside { border-right: 1px solid #2a2e38; overflow: auto; background: #141720; }
    .segment { padding: 10px 12px; border-bottom: 1px solid #242936; cursor: pointer; }
    .segment:hover, .segment.active { background: #232938; }
    .segment strong { display: block; font-size: 13px; }
    .segment span { display: block; color: #aeb6c7; font-size: 12px; margin-top: 3px; }
    section { overflow: auto; padding: 18px; }
    .panel { max-width: 920px; background: #171a21; border: 1px solid #2a2e38; border-radius: 12px; padding: 16px; }
    .grid { display: grid; grid-template-columns: repeat(4, minmax(120px, 1fr)); gap: 12px; }
    label { display: grid; gap: 6px; color: #aeb6c7; font-size: 12px; }
    input, select { border: 1px solid #353b4a; background: #10131a; color: #fff; border-radius: 8px; padding: 8px; font: inherit; }
    audio { width: 100%; margin: 8px 0 14px; }
    .row { display: flex; flex-wrap: wrap; gap: 8px; align-items: center; margin-top: 14px; }
    .muted { color: #aeb6c7; }
    pre { background: #0d0f14; border: 1px solid #2a2e38; border-radius: 10px; padding: 12px; max-height: 220px; overflow: auto; white-space: pre-wrap; }
    .pill { display: inline-flex; border: 1px solid #3a4050; border-radius: 999px; padding: 3px 8px; color: #c9d1e3; font-size: 12px; }
  </style>
</head>
<body>
  <header>
    <h1>Hajimi Segment Editor</h1>
    <button id="reload">重新载入配置</button>
    <button id="recutAll" class="warn">全部重切</button>
    <span class="muted">改完后点“保存 + 重切”，正在运行的 app 下次触发会读新音频。</span>
  </header>
  <main>
    <aside id="segments"></aside>
    <section>
      <div class="panel" id="editor">
        <p class="muted">请选择左侧片段。</p>
      </div>
    </section>
  </main>

  <script>
    let plan = null;
    let selectedId = null;
    let stopTimer = null;

    const $ = (id) => document.getElementById(id);

    async function api(path, options = {}) {
      const res = await fetch(path, {
        headers: { 'content-type': 'application/json' },
        ...options
      });
      const data = await res.json();
      if (!res.ok) throw new Error(data.error || res.statusText);
      return data;
    }

    function esc(value) {
      return String(value ?? '').replace(/[&<>"']/g, (ch) => ({
        '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;'
      })[ch]);
    }

    async function loadPlan() {
      plan = await api('/api/plan');
      selectedId ||= plan.segments[0]?.id;
      renderSegments();
      renderEditor();
    }

    function renderSegments() {
      $('segments').innerHTML = plan.segments.map((s) => `
        <div class="segment ${s.id === selectedId ? 'active' : ''}" data-id="${esc(s.id)}">
          <strong>${esc(s.id)} · ${esc(s.title)}</strong>
          <span>${esc(s.source)} | start=${s.start}s | duration=${s.duration}s</span>
        </div>
      `).join('');
      document.querySelectorAll('.segment').forEach((el) => {
        el.onclick = () => { selectedId = el.dataset.id; renderSegments(); renderEditor(); };
      });
    }

    function segment() {
      return plan.segments.find((s) => s.id === selectedId);
    }

    function renderEditor() {
      const s = segment();
      if (!s) return;

      $('editor').innerHTML = `
        <h2>${esc(s.title)} <span class="pill">${esc(s.id)}</span></h2>
        <p class="muted">源曲：${esc(s.source)}，输出：${esc(s.output)}</p>

        <h3>原曲预览</h3>
        <audio id="rawAudio" controls src="${s.rawUrl}"></audio>
        <div class="row">
          <button class="primary" id="playRawSegment">播放原曲当前区间</button>
          <button id="stopRaw">停止</button>
        </div>

        <h3>已裁剪片段</h3>
        <audio id="clipAudio" controls src="${s.clipUrl}?t=${Date.now()}"></audio>

        <h3>裁剪参数</h3>
        <div class="grid">
          <label>标题 <input id="title" value="${esc(s.title)}" /></label>
          <label>源曲
            <select id="source">
              ${plan.rawFiles.map((f) => `<option ${f === s.source ? 'selected' : ''}>${esc(f)}</option>`).join('')}
            </select>
          </label>
          <label>开始秒数 start <input id="start" type="number" step="0.01" value="${s.start}" /></label>
          <label>时长 duration <input id="duration" type="number" step="0.01" value="${s.duration}" /></label>
          <label>淡入 fadeIn <input id="fadeIn" type="number" step="0.01" value="${s.fadeIn ?? 0.04}" /></label>
          <label>淡出 fadeOut <input id="fadeOut" type="number" step="0.01" value="${s.fadeOut ?? 0.25}" /></label>
          <label>音量 volume <input id="volume" type="number" step="0.01" min="0" max="1" value="${s.volume ?? 1}" /></label>
        </div>

        <div class="row">
          <button id="save">保存配置</button>
          <button id="recut">重切当前片段</button>
          <button class="primary" id="saveRecut">保存 + 重切</button>
        </div>
        <pre id="log">ready</pre>
      `;

      $('playRawSegment').onclick = playRawSegment;
      $('stopRaw').onclick = () => { clearTimeout(stopTimer); $('rawAudio').pause(); };
      $('save').onclick = saveSegment;
      $('recut').onclick = recutSegment;
      $('saveRecut').onclick = async () => { await saveSegment(); await recutSegment(); };
    }

    function currentPayload() {
      return {
        title: $('title').value,
        source: $('source').value,
        start: Number($('start').value),
        duration: Number($('duration').value),
        fadeIn: Number($('fadeIn').value),
        fadeOut: Number($('fadeOut').value),
        volume: Number($('volume').value)
      };
    }

    function playRawSegment() {
      const s = segment();
      const audio = $('rawAudio');
      clearTimeout(stopTimer);
      audio.currentTime = Number($('start').value);
      audio.play();
      stopTimer = setTimeout(() => audio.pause(), Number($('duration').value) * 1000);
    }

    async function saveSegment() {
      const result = await api(`/api/segments/${encodeURIComponent(selectedId)}`, {
        method: 'POST',
        body: JSON.stringify(currentPayload())
      });
      plan = result.plan;
      renderSegments();
      renderEditor();
      $('log').textContent = 'saved';
    }

    async function recutSegment() {
      $('log').textContent = 'recutting...';
      const result = await api(`/api/recut/${encodeURIComponent(selectedId)}`, { method: 'POST', body: '{}' });
      $('log').textContent = result.output || 'recut done';
      await loadPlan();
      $('clipAudio')?.load();
    }

    $('reload').onclick = loadPlan;
    $('recutAll').onclick = async () => {
      $('recutAll').textContent = '全部重切中...';
      try { await api('/api/recut-all', { method: 'POST', body: '{}' }); await loadPlan(); }
      finally { $('recutAll').textContent = '全部重切'; }
    };

    loadPlan().catch((err) => { $('editor').innerHTML = `<pre>${esc(err.stack || err)}</pre>`; });
  </script>
</body>
</html>
"""


def read_plan() -> dict:
    return json.loads(PLAN_PATH.read_text())


def write_plan(plan: dict) -> None:
    PLAN_PATH.write_text(json.dumps(plan, ensure_ascii=False, indent=2) + "\n")


def response_payload(plan: dict) -> dict:
    raw_files = sorted(path.name for path in RAW_DIR.glob("*.WAV"))
    enriched = []
    for segment in plan["segments"]:
        item = dict(segment)
        item["rawUrl"] = "/raw/" + urllib.parse.quote(segment["source"])
        item["clipUrl"] = "/clips/" + urllib.parse.quote(Path(segment["output"]).name)
        enriched.append(item)
    return {**plan, "segments": enriched, "rawFiles": raw_files}


def recut(segment_id: str | None = None) -> str:
    command = ["python3", str(RECUT_SCRIPT)]
    if segment_id:
        command += ["--only", segment_id]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(result.stderr or result.stdout or f"recut failed with {result.returncode}")
    return (result.stdout + result.stderr).strip()


def safe_file(directory: Path, name: str) -> Path:
    candidate = (directory / urllib.parse.unquote(name)).resolve()
    if directory.resolve() not in candidate.parents and candidate != directory.resolve():
        raise ValueError("invalid path")
    if not candidate.exists():
        raise FileNotFoundError(candidate)
    return candidate


class Handler(BaseHTTPRequestHandler):
    def do_GET(self) -> None:
        try:
            if self.path == "/" or self.path.startswith("/?"):
                self.send_bytes(INDEX_HTML.encode(), "text/html; charset=utf-8")
            elif self.path == "/api/plan":
                self.send_json(response_payload(read_plan()))
            elif self.path.startswith("/raw/"):
                self.send_file(safe_file(RAW_DIR, self.path.removeprefix("/raw/")))
            elif self.path.startswith("/clips/"):
                self.send_file(safe_file(CLIPS_DIR, self.path.removeprefix("/clips/").split("?", 1)[0]))
            else:
                self.send_error(HTTPStatus.NOT_FOUND)
        except Exception as error:
            self.send_json({"error": str(error)}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def do_POST(self) -> None:
        try:
            if self.path.startswith("/api/segments/"):
                segment_id = urllib.parse.unquote(self.path.removeprefix("/api/segments/"))
                payload = self.read_json()
                plan = read_plan()
                for segment in plan["segments"]:
                    if segment["id"] == segment_id:
                        for key in ["title", "source", "start", "duration", "fadeIn", "fadeOut", "volume"]:
                            if key in payload:
                                segment[key] = payload[key]
                        write_plan(plan)
                        self.send_json({"plan": response_payload(plan)})
                        return
                self.send_json({"error": "segment not found"}, HTTPStatus.NOT_FOUND)
            elif self.path.startswith("/api/recut/"):
                segment_id = urllib.parse.unquote(self.path.removeprefix("/api/recut/"))
                self.send_json({"output": recut(segment_id), "plan": response_payload(read_plan())})
            elif self.path == "/api/recut-all":
                self.send_json({"output": recut(), "plan": response_payload(read_plan())})
            else:
                self.send_json({"error": "not found"}, HTTPStatus.NOT_FOUND)
        except Exception as error:
            self.send_json({"error": str(error)}, HTTPStatus.INTERNAL_SERVER_ERROR)

    def read_json(self) -> dict:
        length = int(self.headers.get("content-length", "0"))
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def send_json(self, payload: dict, status: HTTPStatus = HTTPStatus.OK) -> None:
        self.send_bytes(json.dumps(payload, ensure_ascii=False).encode(), "application/json; charset=utf-8", status)

    def send_file(self, path: Path) -> None:
        content_type = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
        self.send_response(HTTPStatus.OK)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(path.stat().st_size))
        self.end_headers()
        with path.open("rb") as file:
            while chunk := file.read(1024 * 512):
                self.wfile.write(chunk)

    def send_bytes(self, body: bytes, content_type: str, status: HTTPStatus = HTTPStatus.OK) -> None:
        self.send_response(status)
        self.send_header("content-type", content_type)
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args) -> None:
        print(f"[segment-ui] {self.address_string()} {format % args}")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Local web UI for editing Hajimi shortcut segments.")
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    parser.add_argument("--open", action="store_true")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    server = ThreadingHTTPServer((args.host, args.port), Handler)
    url = f"http://{args.host}:{args.port}"
    print(f"Segment editor running at {url}")
    if args.open:
        webbrowser.open(url)
    server.serve_forever()


if __name__ == "__main__":
    main()
