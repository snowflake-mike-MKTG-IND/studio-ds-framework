# Visualizations

A visualization is the right deliverable when the audience needs to *see a shape* in order to
decide. It is the wrong deliverable when the shape is already known and the decision is
already made, or when the chart exists so nobody has to state a conclusion.

## When to lean on visualization

**The comparison is the point.** Ranked lists, distributions, cohorts side by side. The eye
does the aggregation faster than prose can describe it.

**The trend matters more than the level.** Direction, inflection, and seasonality are
expensive to describe in sentences and immediate in a line.

**The claim needs an error bar.** A point forecast reported as a number invites false
precision. The same forecast as an interval communicates uncertainty without a paragraph of
hedging.

**The audience will interrogate it.** If the next question is predictably "what about
segment B", ship the chart with the breakout rather than answering three follow-ups.

## When not to

**One number.** A single metric is a sentence. A gauge chart around one number is decoration
that costs a render and communicates less than the number did.

**The chart is standing in for a recommendation.** Six panels with no stated conclusion moves
the analytical work onto the reader. If you know what the data says, say it, and use one chart
as evidence.

**Nobody has asked twice.** Building a dashboard for a question asked once is the most common
way DS capacity gets absorbed. Answer it, and wait to see if it recurs.

## Cost characteristics

Rendering an existing chart from known SQL requires no model inference. Asking CoCo to
generate or interpret it still uses tokens. Warehouse, application hosting, storage, and
refresh costs remain; there is no universal ranking that makes every chart cheaper than
every agent response.

Two rules keep it cheap:

**Aggregate in SQL, not in the client.** Pulling raw rows to a dashboard and summarizing in
Python or JavaScript pays for scanning and transferring data you discard. Push the `GROUP BY`
into the warehouse.

**Give recurring dashboards a materialized source.** A dashboard that runs the same
aggregation on every load, for every viewer, is the clearest case for a scheduled table or a
dynamic table. The refresh is one query; the dashboard becomes a cheap point read.

## Interaction with agents

An agent should render charts, not invent them. The durable pattern is a small set of
approved chart specifications that the agent selects from and parameterizes, with the
underlying query coming from the semantic layer. Letting an agent write both the query and
the chart on every request produces visually confident output whose numbers cannot be
reconciled between two runs.
