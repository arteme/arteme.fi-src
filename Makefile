
RSTBLOG = https://github.com/mitsuhiko/rstblog.git
PACKAGES = pygments

ENV = _env
BIN = $(ENV)/bin
INSTALLED = $(ENV)/.installed

all: serve

env $(INSTALLED):
	mkdir -p $(ENV)
	virtualenv --no-site-packages $(ENV)
	$(BIN)/pip install $(PACKAGES)
	git clone $(RSTBLOG) $(ENV)/rstblog
	(cd $(ENV)/rstblog && ../../$(BIN)/python setup.py develop)
	touch $(INSTALLED)
	
build: $(INSTALLED)
	$(BIN)/python $(BIN)/run-rstblog build

serve: $(INSTALLED)
	$(BIN)/python $(BIN)/run-rstblog serve

clean:
	rm -rf $(ENV) _build

