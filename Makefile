GUILE ?= guile
GUILE_FLAGS = --fresh-auto-compile -L .

TESTS = $(wildcard tests/*.scm)

.PHONY: check clean golden manual manual-serve preview

check:
	@status=0; \
	for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(GUILE) $(GUILE_FLAGS) $$t || status=1; \
	done; \
	exit $$status

# Rewrite tests/golden/ from examples/ after an intended output change.
golden:
	$(GUILE) $(GUILE_FLAGS) tests/golden.scm --update

# Draw each golden figure with typst/notasi.typ, to build/preview/NAME.png,
# for a person to compare with doc/prototypes/score.typ. Needs typst.
preview:
	@mkdir -p build/preview
	@for f in tests/golden/*.json; do \
	  n=$$(basename $$f .json); \
	  printf '#import "/typst/notasi.typ": score\n#set page(width: auto, height: auto, margin: 14pt, fill: white)\n#set text(size: 8pt)\n#score(json("/%s"))\n' "$$f" > build/preview/$$n.typ; \
	  typst compile --root . --ppi 144 build/preview/$$n.typ build/preview/$$n.png && echo "wrote build/preview/$$n.png"; \
	done

clean:
	rm -f *.log tests/*.log
	rm -rf doc/manual/book

# The user manual (doc/manual/), built with mdBook into doc/manual/book/.
manual:
	mdbook build doc/manual

manual-serve:
	mdbook serve doc/manual --open
