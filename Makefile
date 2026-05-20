.PHONY: dist clean

SKILLS = reasonhub-snomed-semantic \
         reasonhub-clinical-search \
         reasonhub-terminology-crossmap \
         reasonhub-expand-mechanics

DIST_FILE = dist/claude-desktop.md

# Strip YAML frontmatter (everything between and including the first two --- lines)
STRIP_FRONT = awk '/^---/{n++; if(n<=2) next} n>=2'

dist: $(DIST_FILE)

$(DIST_FILE): $(foreach s,$(SKILLS),$(s)/SKILL.md) Makefile
	mkdir -p dist
	@printf '# reasonhub-skills — Claude Desktop Instructions\n\n' > $@
	@printf 'Paste the entire contents of this file into your Claude Desktop\n' >> $@
	@printf 'Project'\''s custom instructions (gear icon → Project Instructions).\n' >> $@
	@printf 'Requires the ReasonHub MCP server configured in\n' >> $@
	@printf '`claude_desktop_config.json` — see README for the config block.\n\n' >> $@
	@for skill in $(SKILLS); do \
		printf '\n---\n\n' >> $@; \
		$(STRIP_FRONT) $$skill/SKILL.md >> $@; \
	done
	@echo "Generated $(DIST_FILE)"

clean:
	rm -rf dist
