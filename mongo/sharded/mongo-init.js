const testDb = db.getSiblingDB('test');

db.test.createIndex({field: 1}, {unique: true})
sh.shardCollection('test.test', {field: 1}, true)

sh.addShardToZone('shard0', 'shard-0')
sh.addShardToZone('shard1', 'shard-1')