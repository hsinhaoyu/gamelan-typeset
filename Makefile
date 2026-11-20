GUILE ?= guile
GUILE_FLAGS = --fresh-auto-compile -L .

TESTS = $(wildcard tests/*.scm)

.PHONY: check clean manual manual-serve

check:
	@status=0; \
	for t in $(TESTS); do \
	  echo "== $$t"; \
	  $(GUILE) $(GUILE_FLAGS) $$t || status=1; \
	done; \
	exit $$status

clean:
	rm -f *.log tests/*.log
	rm -rf doc/manual/book

# The user manual (doc/manual/), built with mdBook into doc/manual/book/.
manual:
	mdbook build doc/manual

manual-serve:
	mdbook serve doc/manual --open
