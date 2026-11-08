WITH sampled AS MATERIALIZED (
 SELECT b.record_id,rank AS relevance,b.id AS block_id
 FROM content_search JOIN content_blocks b INDEXED BY content_block_identity ON b.id=content_search.rowid
 WHERE content_search MATCH ?1 LIMIT 4096
), seed AS MATERIALIZED (
 SELECT s.record_id,min(s.relevance) AS relevance FROM sampled s
 JOIN available_search_records r ON r.id=s.record_id
 LEFT JOIN workspace w ON w.record_id=r.id
 WHERE w.trashed IS NULL
 GROUP BY s.record_id ORDER BY relevance,s.record_id LIMIT 101
), boundary AS MATERIALIZED (
 SELECT relevance,record_id FROM seed WHERE (SELECT count(*) FROM seed)=101
 ORDER BY relevance DESC,record_id DESC LIMIT 1
), scored AS (
 SELECT b.record_id,rank AS relevance,b.id AS block_id
 FROM content_search JOIN content_blocks b INDEXED BY content_block_identity ON b.id=content_search.rowid
 WHERE content_search MATCH ?1 LIMIT -1
), documents AS (
 SELECT record_id,min(relevance) AS relevance,block_id FROM scored
 WHERE NOT EXISTS (SELECT 1 FROM boundary) OR relevance < (SELECT relevance FROM boundary)
 OR (relevance=(SELECT relevance FROM boundary) AND record_id<=(SELECT record_id FROM boundary))
 GROUP BY record_id
)
SELECT d.record_id,d.relevance,d.block_id
FROM documents d JOIN available_search_records r ON r.id=d.record_id
LEFT JOIN workspace w ON w.record_id=r.id WHERE w.trashed IS NULL
ORDER BY d.relevance,d.record_id LIMIT 101
