"use strict";

class ApiClient {
  constructor(baseUrl, apiKey) {
    this.baseUrl = baseUrl.replace(/\/$/, "");
    this.apiKey = apiKey;
  }

  async exportScoring() {
    const res = await fetch(`${this.baseUrl}/api/loot/addon-export`, {
      headers: { "x-api-key": this.apiKey },
      signal: AbortSignal.timeout(30000),
    });
    if (!res.ok) throw new Error(`Export failed: ${res.status} ${await res.text()}`);
    return res.json();
  }

  async awardLoot({ item, awardedTo, awardedBy, boss, timestamp }) {
    const res = await fetch(`${this.baseUrl}/api/loot/addon`, {
      method: "POST",
      headers: { "x-api-key": this.apiKey, "Content-Type": "application/json", "Host": "nordavind.cc" },
      body: JSON.stringify({ item, awardedTo, awardedBy, boss, timestamp }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) throw new Error(`Award failed: ${res.status} ${await res.text()}`);
    return res.json();
  }

  async editAward({ originalTimestamp, item, newAwardedTo, newCategory }) {
    const res = await fetch(`${this.baseUrl}/api/loot/addon`, {
      method: "PATCH",
      headers: { "x-api-key": this.apiKey, "Content-Type": "application/json", "Host": "nordavind.cc" },
      body: JSON.stringify({ originalTimestamp, item, newAwardedTo, newCategory }),
      signal: AbortSignal.timeout(10000),
    });
    if (!res.ok) throw new Error(`Edit failed: ${res.status} ${await res.text()}`);
    return res.json();
  }
}

module.exports = { ApiClient };
