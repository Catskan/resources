// ==UserScript==
// @name         Leboncoin Prefill from vinted-bot
// @namespace    https://github.com/aurelien/vinted-bot
// @version      0.1.0
// @description  Pré-remplit le formulaire "Déposer une annonce" Leboncoin depuis la queue JSON du NAS
// @author       aurelien
// @match        https://www.leboncoin.fr/ai/new*
// @match        https://www.leboncoin.fr/deposer-une-annonce*
// @grant        GM_xmlhttpRequest
// @connect      *
// @run-at       document-idle
// ==/UserScript==

(function () {
  "use strict";

  // URL du queue.json exposé par le NAS (à configurer en Phase 4).
  // Options possibles :
  //   - Synology Drive partagé (lien direct)
  //   - Web Station Synology (http://nas.local/queue.json)
  //   - Bind mount + nginx léger
  const QUEUE_URL = "http://nas.local/vinted-bot/queue.json";

  async function fetchQueue() {
    try {
      const resp = await fetch(QUEUE_URL);
      return await resp.json();
    } catch (e) {
      console.warn("[vinted-bot] queue indisponible :", e);
      return [];
    }
  }

  function prefillForm(_item) {
    // TODO Phase 4 : mapper champs JSON → inputs Leboncoin.
    // Les sélecteurs Leboncoin changent souvent, à actualiser via DevTools.
  }

  async function main() {
    const queue = await fetchQueue();
    if (!queue.length) return;
    console.log(`[vinted-bot] ${queue.length} item(s) en queue`);
    prefillForm(queue[0]);
  }

  main();
})();
