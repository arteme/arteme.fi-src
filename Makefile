DEPLOY = git@github.com:arteme/arteme.github.com.git

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

################################################################

_deploy/.git/config:
	git clone $(DEPLOY) _deploy


deploy:: _deploy/.git/config build
	cd _deploy && git ls-files -z | xargs -0 rm -f
	cp -R _build/* _deploy
	cp _build/404/index.html _deploy/404.html
	cd _deploy && git add -A
	cd _deploy && git commit -m "Update: `date --rfc-3339=seconds`"
	cd _deploy && git push -n
