# Cortex Search for reports

Cortex Search is a managed retrieval service over text. In a reporting workflow its job is to
supply **evidence and context**, not figures. Every number in a report should come from the
semantic layer. Every quotation, theme, and explanation can come from Search.

## When Search is the right tool

**The corpus is unstructured and large.** Research decks, exhibitor notes, review text, social
comments, press, meeting transcripts. Anything where the answer is a passage rather than a
value.

**The report needs to cite.** Retrieval returns the source chunk, so a claim can carry its
provenance. This is the difference between a report a stakeholder trusts and one they
relitigate.

**The question is thematic.** "What concerns keep coming up about this title" has no
aggregation that produces it. Retrieval plus synthesis does.

**The corpus changes and the questions do not.** A Search service refreshed on a schedule
answers the same standing questions against new material with no pipeline rewrite.

## When Search is the wrong tool

**Counting.** "How many mentions were negative" is an aggregation over a scored column, not a
retrieval. Classify once with AISQL, materialize the labels, then count in SQL. Asking a
retrieval service to count returns the count of what it retrieved, which is a sample, and it
will look like an answer.

**Anything numeric.** Retrieval has no notion of completeness. Ten relevant chunks are not ten
of ten.

**Small fixed corpora.** Under a few hundred documents that fit a single pass, an indexed
service adds operational surface for little gain.

## The division of labor in one report

```
Semantic layer  -> every figure, every delta, every ranking
Cortex Search   -> the passages that explain the figures
AISQL, batch    -> the labels the figures aggregate over
Agent           -> assembly and prose, nothing else
```

The agent should not be able to produce a number that did not come from the semantic layer.
Enforcing this in the skill's acceptance criteria is what makes a generated report auditable.

## Cost characteristics

For standard interactive Search, costs include warehouse refresh, embedding new/changed
rows, serving indexed data, storage, and applicable cloud services. Serving is charged
by indexed GB-month while available, including idle time, not per returned chunk or
query. Batch Search has its own billing model. The queries in `sql/40_cost_observability.sql`
separate embedding and serving; they do not include refresh warehouse or storage cost.

Practical cost rules:

**Set the refresh lag to the business need.** A corpus that changes weekly does not need
a one-minute target lag. Define service primary keys, update sources incrementally,
and avoid replacing source tables or changing their schema unnecessarily: full refreshes
can re-embed the corpus. Check measured usage rather than assuming indexing dominates.

**Index the text, not the table.** Restrict the indexed column set to what retrieval actually
needs, and filter to the corpus that gets queried. Indexing an archive nobody searches is a
recurring charge for nothing.

**Retrieve fewer, better chunks.** Use metadata filters, relevance evaluation, and a total
context-token limit. Reducing retrieved text reduces downstream synthesis tokens, not
the indexed-size serving charge. Six chunks is a starting point, not a universal optimum;
measure whether omitted evidence hurts answer quality.

**Suspend unused serving.** Use supported manual or automatic serving suspension for
idle development services when the startup/freshness tradeoff is acceptable.

Sources: [Search cost considerations](https://docs.snowflake.com/en/user-guide/snowflake-cortex/cortex-search/cortex-search-costs)
and [batch Search metering](https://docs.snowflake.com/en/sql-reference/account-usage/cortex_search_batch_query_usage_history).
