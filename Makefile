APP := build/Prometheus.app

.PHONY: app run install clean

app:
	@./scripts/build-app.sh

run: app
	@open "$(APP)"

install: app
	@rm -rf "/Applications/Prometheus.app" "/Applications/Medonom.app" "/Applications/Loupe.app" "/Applications/Local AI Agent.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications/Prometheus.app"

clean:
	@rm -rf .build build
