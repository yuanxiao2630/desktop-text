.PHONY: build universal test run clean

build:
	python3 scripts/build.py

universal:
	python3 scripts/build.py --arch universal

test: build
	"dist/桌面文字.app/Contents/MacOS/DesktopText" --self-test

run: build
	open "dist/桌面文字.app"

clean:
	python3 -c "from pathlib import Path; import shutil; [shutil.rmtree(p) for p in (Path('.build'), Path('dist')) if p.is_dir()]"
