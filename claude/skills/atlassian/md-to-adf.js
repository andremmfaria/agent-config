#!/usr/bin/env node
'use strict';

// Official Atlassian markdown → ADF conversion pipeline.
// Uses @atlaskit/editor-markdown-transformer + @atlaskit/editor-json-transformer
// installed in this skill's node_modules (both ship CJS via their `main` field).

const path = require('path');
const fs = require('fs');

const SKILL_DIR = path.resolve(__dirname);

if (process.argv.length !== 4) {
  console.error('Usage: node md-to-adf.js INPUT.md OUTPUT.json');
  process.exit(1);
}

const inputPath = process.argv[2];
const outputPath = process.argv[3];

if (!fs.existsSync(inputPath)) {
  console.error(`Error: input file not found: ${inputPath}`);
  process.exit(1);
}

// Require from the skill's own node_modules so this works regardless of cwd.
const { MarkdownTransformer } = require(path.join(SKILL_DIR, 'node_modules/@atlaskit/editor-markdown-transformer'));
const { JSONTransformer } = require(path.join(SKILL_DIR, 'node_modules/@atlaskit/editor-json-transformer'));

const markdownString = fs.readFileSync(inputPath, 'utf8');

const md = new MarkdownTransformer();
const json = new JSONTransformer();
const adf = json.encode(md.parse(markdownString));

fs.writeFileSync(outputPath, JSON.stringify(adf, null, 2), 'utf8');

console.log(`ADF written to ${outputPath} (${adf.content.length} top-level nodes)`);
