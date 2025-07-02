app.js: app.tsx ../ReactNotive/index.ts ../ReactNotive/nativeElements.ts
	bun build --outfile=$@ $<

check:
	./node_modules/.bin/tsc --noEmit

clean:
	rm -f app.js

.PHONY: check clean
