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

# Draw each example in examples/ with render-piece, to build/preview/NAME.png,
# for a person to check how figures look. Needs typst.
preview:
	@mkdir -p build/preview
	@for f in examples/*.gml; do \
	  n=$$(basename $$f .gml); \
	  $(GUILE) -L . -c "(use-modules (notasi typst)) (render-piece \"$$f\" \"build/preview/$$n.png\")" \
	    && echo "wrote build/preview/$$n.png"; \
	done

clean:
	rm -f *.log tests/*.log
	rm -rf doc/manual/book

# The user manual (doc/manual/), built with mdBook into doc/manual/book/.
manual:
	mdbook build doc/manual

manual-serve:
	mdbook serve doc/manual --open
