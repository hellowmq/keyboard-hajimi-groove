.PHONY: recut-hajimi recut-hajimi-one list-hajimi-segments validate-code validate-assets validate-hajimi doctor segment-ui

recut-hajimi:
	python3 Tools/recut_hajimi_segments.py

recut-hajimi-one:
	@test -n "$(ID)" || (echo "Usage: make recut-hajimi-one ID=drop-copy" && exit 1)
	python3 Tools/recut_hajimi_segments.py --only "$(ID)"

list-hajimi-segments:
	python3 Tools/recut_hajimi_segments.py --list

validate-code:
	python3 -m json.tool Samples/hajimi-local/segment-plan.json >/dev/null
	python3 -m json.tool Themes/shortcut-local-drops.json >/dev/null
	swift test

validate-assets:
	@test -n "$$(find Samples/hajimi-local/raw -maxdepth 1 -name '*.WAV' -print -quit)" || (echo "Missing raw WAV files in Samples/hajimi-local/raw" && exit 1)
	@test -n "$$(find Samples/hajimi-local/clips -maxdepth 1 -name '*.m4a' -print -quit)" || (echo "Missing generated clips in Samples/hajimi-local/clips. Run make recut-hajimi after adding raw files." && exit 1)
	@for f in Samples/hajimi-local/clips/*.m4a; do afinfo "$$f" >/dev/null || exit 1; done

validate-hajimi: validate-code validate-assets

doctor:
	@command -v swift >/dev/null || (echo "Missing swift" && exit 1)
	@command -v ffmpeg >/dev/null || (echo "Missing ffmpeg" && exit 1)
	@command -v afinfo >/dev/null || (echo "Missing afinfo" && exit 1)
	@python3 -m json.tool Samples/hajimi-local/segment-plan.json >/dev/null
	@python3 -m json.tool Themes/shortcut-local-drops.json >/dev/null
	@raw_count=$$(find Samples/hajimi-local/raw -maxdepth 1 -name '*.WAV' | wc -l | tr -d ' '); \
	clip_count=$$(find Samples/hajimi-local/clips -maxdepth 1 -name '*.m4a' | wc -l | tr -d ' '); \
	echo "swift: $$(swift --version | head -n 1)"; \
	echo "ffmpeg: $$(ffmpeg -version | head -n 1)"; \
	echo "raw WAV files: $$raw_count"; \
	echo "generated clips: $$clip_count"; \
	if [ "$$raw_count" = "0" ]; then echo "Next: add WAV files to Samples/hajimi-local/raw"; fi; \
	if [ "$$raw_count" != "0" ] && [ "$$clip_count" = "0" ]; then echo "Next: run make recut-hajimi"; fi
	swift test

segment-ui:
	python3 Tools/segment_editor_server.py --open
