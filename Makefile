APP := build/Loupe.app

.PHONY: app run install clean

app:
	@./scripts/build-app.sh

run: app
	@open "$(APP)"

install: app
	@rm -rf "/Applications/Loupe.app" "/Applications/Local AI Agent.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications/Loupe.app"

clean:
	@rm -rf .build build
