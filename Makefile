APP := build/Prometheus.app
LAB := build/Prometheus Lab.app

.PHONY: app lab run run-lab install install-lab clean

# The public app: one harness, the amber flame.
app:
	@./scripts/build-app.sh

# The private app, Prometheus Lab: every harness version, the pink flame.
lab:
	@EDITION=lab ./scripts/build-app.sh

run: app
	@open "$(APP)"

run-lab: lab
	@open "$(LAB)"

install: app
	@rm -rf "/Applications/Prometheus.app" "/Applications/Medonom.app" "/Applications/Loupe.app" "/Applications/Local AI Agent.app"
	@cp -R "$(APP)" /Applications/
	@echo "✓ Installed to /Applications/Prometheus.app"

install-lab: lab
	@rm -rf "/Applications/Prometheus Lab.app"
	@cp -R "$(LAB)" /Applications/
	@echo "✓ Installed to /Applications/Prometheus Lab.app"

clean:
	@rm -rf .build build
