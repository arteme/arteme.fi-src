
#REPO = https://github.com/mitsuhiko/rstblog.git
REPO = git@github.com:arteme/rstblog.git
EGGS = pygments

RST = _rstblog

BOOTSTRAP = $(RST)/bootstrap.py
BUILDOUT = $(RST)/bin/buildout
RUN = $(RST)/bin/run-rstblog

all: serve

$(BOOTSTRAP):
	git clone $(REPO) $(RST)

$(BUILDOUT): $(BOOTSTRAP)
	cd $(RST) && python bootstrap.py

$(RUN): $(BUILDOUT)
	cd $(RST) && bin/buildout -n $(patsubst %,buildout:eggs+=%,$(EGGS))

################################################################
	
build: $(RUN)
	$(RUN) build

serve: $(RUN)
	$(RUN) serve

clean:
	rm -rf _build

distclean: clean
	rm -rf $(_RST)


