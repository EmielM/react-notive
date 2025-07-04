app.js: app.tsx ../ReactNotive/index.ts ../ReactNotive/nativeElements.ts
	bun build --outfile=$@ $<

app.production.js: app.tsx ../ReactNotive/index.ts ../ReactNotive/nativeElements.ts
	bun build --outfile=$@ --production $<

check:
	./node_modules/.bin/tsc --noEmit

clean:
	rm -f app.js

.PHONY: check clean
