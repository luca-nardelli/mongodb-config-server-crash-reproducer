import { MongoClient } from 'mongodb';
import { faker } from '@faker-js/faker';

async function main() {
  const client = await MongoClient.connect('mongodb://admin:password@localhost:27017?authSource=admin');
  const db = client.db('test');

  const testCollection = db.collection('test');

  const ITERS = 50;

  for (let i = 0; i < 50; i++) {
    const items = Array.from(Array(10_000).keys()).map(i => ({
      field: faker.string.hexadecimal({ length: 40 }),
    }));
    await testCollection.insertMany(items);
    console.log(`Inserted ${i}/${ITERS}`);
  }

  await client.close();
}

main();