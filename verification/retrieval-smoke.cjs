// Run inside the pinned AnythingLLM container; does not call an LLM provider.
const { createRequire } = require('node:module');
const appRequire = createRequire('/app/server/package.json');
appRequire('dotenv').config({ path: '/app/server/.env' });
const { NativeEmbedder } = appRequire('./utils/EmbeddingEngines/native');
const { LanceDb } = appRequire('./utils/vectorDbProviders/lance');

(async () => {
  const embedder = new NativeEmbedder();
  if (embedder.model !== 'MintplexLabs/multilingual-e5-small') {
    throw new Error('Unexpected embedding model; avoid changing an existing index silently.');
  }
  const store = new LanceDb();
  const namespace = process.argv[2] || 'moya-baza-znanij';
  const checks = [
    { question: 'Сколько длится занятие?', expected: '45 минут' },
    { question: 'Сколько человек можно принять на один урок?', expected: '12 человек' },
  ];
  const results = [];
  for (const check of checks) {
    const found = await store.performSimilaritySearch({
      namespace,
      input: check.question,
      LLMConnector: embedder,
      similarityThreshold: 0,
      topN: 4,
    });
    const passed = found.contextTexts.some(text => text.includes(check.expected)) && found.sources.length > 0;
    results.push({ question: check.question, relevantTextFound: passed, sourceCount: found.sources.length });
  }
  console.log(JSON.stringify({ scope: 'Retrieval only; LLM answers are not tested.', model: embedder.model, results }));
  process.exit(results.every(result => result.relevantTextFound) ? 0 : 1);
})().catch(error => { console.error(error.message); process.exit(1); });
