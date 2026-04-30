#!/usr/bin/env node
/**
 * Import ../docs/*.md into src/content/docs/ for Starlight.
 *
 * This script runs as a `prebuild` hook (see package.json scripts). It
 * copies the raw markdown from the monorepo's docs/ directory into the
 * Starlight content tree, inserts the YAML front matter Starlight needs
 * (title, description, sidebar order), and rewrites cross-doc links
 * from the docs/ layout (`[x](OTHER.md)`) to the Starlight layout
 * (`/section/slug/`).
 *
 * The src/content/docs/ tree is gitignored — this script is the single
 * source of truth for how docs get shaped for the website. Edit the
 * MAPPING table below to add/remove/rename pages.
 */

import { readFile, writeFile, mkdir, rm } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = dirname(__filename);

const WEBSITE_ROOT = resolve(__dirname, '..');
const REPO_ROOT = resolve(WEBSITE_ROOT, '..');
const DOCS_SRC = join(REPO_ROOT, 'docs');
const DOCS_DEST = join(WEBSITE_ROOT, 'src', 'content', 'docs');

/**
 * Mapping: source filename → { section, slug, sidebarOrder, title }.
 * Order here drives both the destination path and the sidebar position.
 * The `title` overrides the H1 (Starlight often wants shorter nav labels
 * than the H1 would give us).
 */
const MAPPING = [
	// Getting started
	{
		src: 'QUICKSTART.md',
		section: 'getting-started',
		slug: 'quickstart',
		order: 1,
		title: '5-Minute Quickstart',
	},
	{
		src: 'faq.md',
		section: 'getting-started',
		slug: 'faq',
		order: 2,
		title: 'FAQ',
	},
	{
		src: 'access-guide.md',
		section: 'getting-started',
		slug: 'access',
		order: 3,
		title: 'Access guide',
	},

	// Reference
	{
		src: 'mcp-tools.md',
		section: 'reference',
		slug: 'mcp-tools',
		order: 1,
		title: 'MCP tools',
	},
	{
		src: 'benchmark-report.md',
		section: 'reference',
		slug: 'benchmarks',
		order: 2,
		title: 'Benchmarks',
	},
	{
		src: 'storage-options.md',
		section: 'reference',
		slug: 'storage',
		order: 3,
		title: 'Storage options',
	},

	// Operating
	{
		src: 'examples.md',
		section: 'operating',
		slug: 'examples',
		order: 1,
		title: 'Examples',
	},
	{
		src: 'clusterclaw-deployment-plan.md',
		section: 'operating',
		slug: 'deployment',
		order: 2,
		title: 'Deployment',
	},
	{
		src: 'roadmap.md',
		section: 'operating',
		slug: 'roadmap',
		order: 3,
		title: 'Roadmap',
	},
];

/** Build a lookup so we can rewrite cross-doc links. */
const FILENAME_TO_DEST = new Map();
for (const entry of MAPPING) {
	FILENAME_TO_DEST.set(entry.src, `/${entry.section}/${entry.slug}/`);
}

/**
 * Extract a one-sentence description from the first paragraph of body
 * text (skipping the H1 and any blank lines). Used for OG tags and
 * sidebar subtitles.
 */
function extractDescription(body) {
	const lines = body.split('\n');
	let i = 0;
	// Skip the first H1
	while (i < lines.length && !lines[i].startsWith('# ')) i++;
	i++; // past the H1
	// Skip blank lines
	while (i < lines.length && lines[i].trim() === '') i++;
	// Collect until the next blank line or heading
	const collected = [];
	while (
		i < lines.length &&
		lines[i].trim() !== '' &&
		!lines[i].startsWith('#')
	) {
		collected.push(lines[i]);
		i++;
	}
	const first = collected.join(' ').trim();
	// Trim to ~160 chars for clean OG tags
	if (first.length <= 160) return first;
	return first.slice(0, 157).trimEnd() + '…';
}

/**
 * Strip the H1 from the body (Starlight renders `title` from front
 * matter, so having the H1 in the body too would duplicate the heading).
 */
function stripH1(body) {
	const lines = body.split('\n');
	let i = 0;
	while (i < lines.length && !lines[i].startsWith('# ')) i++;
	if (i >= lines.length) return body;
	// Drop the H1 line and any blank lines that immediately follow it
	lines.splice(i, 1);
	while (i < lines.length && lines[i].trim() === '') {
		lines.splice(i, 1);
		break; // only strip one leading blank line
	}
	return lines.join('\n');
}

/**
 * Rewrite cross-doc markdown links.
 *
 * `[x](OTHER.md)`              → `[x](/section/slug/)`
 * `[x](OTHER.md#heading)`      → `[x](/section/slug/#heading)`
 * `[x](../docs/OTHER.md)`      → `[x](/section/slug/)`
 * `[x](docs/OTHER.md)`         → `[x](/section/slug/)`
 *
 * Links we don't know about (e.g. `[x](../LICENSE)`, absolute URLs,
 * relative paths into `examples/`) pass through unchanged — they will
 * 404 if clicked in the docs site, which is usually fine because the
 * target isn't part of the docs tree anyway.
 */
function rewriteLinks(body) {
	return body.replace(
		/\[([^\]]+)\]\(([^)]+)\)/g,
		(match, text, href) => {
			// Strip optional leading "./" or "../docs/" or "docs/"
			let normalized = href.trim();
			normalized = normalized.replace(/^\.\//, '');
			normalized = normalized.replace(/^\.\.\/docs\//, '');
			normalized = normalized.replace(/^docs\//, '');

			// Split off any #fragment
			const hashIdx = normalized.indexOf('#');
			const bare = hashIdx >= 0 ? normalized.slice(0, hashIdx) : normalized;
			const hash = hashIdx >= 0 ? normalized.slice(hashIdx) : '';

			const dest = FILENAME_TO_DEST.get(bare);
			if (!dest) return match;
			return `[${text}](${dest}${hash})`;
		}
	);
}

/**
 * YAML-escape a string for use in front matter. Minimal — just handles
 * the cases we actually hit (quotes, newlines). Since titles and
 * descriptions come from our own docs we can trust them to be
 * well-formed; we just quote and escape any embedded double quotes.
 */
function yamlString(s) {
	return `"${s.replace(/\\/g, '\\\\').replace(/"/g, '\\"')}"`;
}

async function clean() {
	await rm(DOCS_DEST, { recursive: true, force: true });
	await mkdir(DOCS_DEST, { recursive: true });
}

async function writeIndex() {
	const indexPath = join(DOCS_DEST, 'index.mdx');
	const body = `---
title: PicoCluster Claw docs
description: Private AI appliance — OpenClaw agents, local LLM inference, ThreadWeaver chat.
template: splash
hero:
  tagline: Private AI on your desk.
  actions:
    - text: Quickstart
      link: /getting-started/quickstart/
      icon: right-arrow
      variant: primary
    - text: View on GitHub
      link: https://github.com/picocluster/picocluster-claw
      icon: external
---

import { Card, CardGrid } from '@astrojs/starlight/components';

<CardGrid>
  <Card title="New here?" icon="rocket">
    Start with the [Quickstart](/getting-started/quickstart/) — plug in
    your cluster, connect, and run your first agent in under five minutes.
  </Card>

  <Card title="MCP tools" icon="puzzle">
    All 28 built-in [MCP tools](/reference/mcp-tools/) documented —
    LEDs, system, LLM bridge, time, and file access across five servers.
  </Card>

  <Card title="Examples" icon="setting">
    See [example prompts](/operating/examples/) for OpenClaw agents —
    cluster control, LED patterns, and AI-assisted workflows.
  </Card>

  <Card title="Benchmarks" icon="open-book">
    Real [benchmark numbers](/reference/benchmarks/) from the Jetson Orin
    Nano Super — inference speed, power draw, and model comparisons.
  </Card>
</CardGrid>
`;
	await writeFile(indexPath, body, 'utf8');
}

async function processOne(entry) {
	const srcPath = join(DOCS_SRC, entry.src);
	const destDir = join(DOCS_DEST, entry.section);
	const destPath = join(destDir, `${entry.slug}.md`);

	const raw = await readFile(srcPath, 'utf8');
	const description = extractDescription(raw);
	const withoutH1 = stripH1(raw);
	const linked = rewriteLinks(withoutH1);

	const frontMatter = [
		'---',
		`title: ${yamlString(entry.title)}`,
		`description: ${yamlString(description)}`,
		`sidebar:`,
		`  order: ${entry.order}`,
		'---',
		'',
	].join('\n');

	await mkdir(destDir, { recursive: true });
	await writeFile(destPath, frontMatter + linked, 'utf8');

	return { entry, bytes: raw.length };
}

async function main() {
	console.log(`[import-docs] source: ${DOCS_SRC}`);
	console.log(`[import-docs] dest:   ${DOCS_DEST}`);

	await clean();
	await writeIndex();

	let totalBytes = 0;
	for (const entry of MAPPING) {
		try {
			const { bytes } = await processOne(entry);
			totalBytes += bytes;
			console.log(
				`[import-docs] ${entry.src.padEnd(24)} → ${entry.section}/${entry.slug}`
			);
		} catch (err) {
			console.error(`[import-docs] ERROR processing ${entry.src}: ${err.message}`);
			process.exitCode = 1;
		}
	}
	console.log(
		`[import-docs] imported ${MAPPING.length} files (${(totalBytes / 1024).toFixed(1)} KiB)`
	);
}

main().catch((err) => {
	console.error('[import-docs] fatal:', err);
	process.exit(1);
});
