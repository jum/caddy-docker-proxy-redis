package main

import (
	"context"
	"log"
	"os"

	"github.com/redis/go-redis/v9"
)

var ctx = context.Background()

func main() {
	sourceAddr := os.Getenv("SOURCE_ADDR")
	if sourceAddr == "" {
		sourceAddr = "127.0.0.1:6379"
	}
	targetAddr := os.Getenv("TARGET_ADDR")
	if targetAddr == "" {
		targetAddr = "127.0.0.1:6380"
	}

	src := redis.NewClient(&redis.Options{
		Addr: sourceAddr,
	})
	dst := redis.NewClient(&redis.Options{
		Addr: targetAddr,
	})

	defer src.Close()
	defer dst.Close()

	// Test connections
	if err := src.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to source Redis (%s): %v", sourceAddr, err)
	}
	if err := dst.Ping(ctx).Err(); err != nil {
		log.Fatalf("Failed to connect to target Valkey (%s): %v", targetAddr, err)
	}

	log.Printf("Connected. Migrating from %s to %s...", sourceAddr, targetAddr)

	var cursor uint64
	var n int
	
	for {
		var keys []string
		var err error
		keys, cursor, err = src.Scan(ctx, cursor, "*", 100).Result()
		if err != nil {
			log.Fatalf("Scan failed: %v", err)
		}

		for _, key := range keys {
			migrateKey(src, dst, key)
			n++
		}

		if cursor == 0 {
			break
		}
	}

	log.Printf("Migration complete. Transferred %d keys.", n)
}

func migrateKey(src, dst *redis.Client, key string) {
	// 1. Get TTL
	ttl, err := src.PTTL(ctx, key).Result()
	if err != nil {
		log.Printf("Failed to get TTL for %s: %v", key, err)
		return
	}

	// 2. Dump is binary-safe but version dependent, so we must use logical types.
	// However, standard Redis DUMP/RESTORE is what caused the issue.
	// We must implement logical copy per type.

	keyType, err := src.Type(ctx, key).Result()
	if err != nil {
		log.Printf("Failed to get type for %s: %v", key, err)
		return
	}

	pipe := dst.Pipeline()
	
	switch keyType {
	case "string":
		val, err := src.Get(ctx, key).Result()
		if err != nil {
			log.Printf("Error reading string %s: %v", key, err)
			return
		}
		pipe.Set(ctx, key, val, 0) // TTL set later

	case "list":
		items, err := src.LRange(ctx, key, 0, -1).Result()
		if err != nil {
			log.Printf("Error reading list %s: %v", key, err)
			return
		}
		if len(items) > 0 {
			pipe.Del(ctx, key) // Clear target first to avoid appending
			pipe.RPush(ctx, key, items)
		}

	case "set":
		members, err := src.SMembers(ctx, key).Result()
		if err != nil {
			log.Printf("Error reading set %s: %v", key, err)
			return
		}
		if len(members) > 0 {
			pipe.Del(ctx, key)
			pipe.SAdd(ctx, key, members)
		}

	case "hash":
		data, err := src.HGetAll(ctx, key).Result()
		if err != nil {
			log.Printf("Error reading hash %s: %v", key, err)
			return
		}
		if len(data) > 0 {
			// HSet accepts map[string]string directly but go-redis signature varies slightly across versions.
			// Passing 'data' usually works for recent versions.
			pipe.Del(ctx, key)
			pipe.HSet(ctx, key, data)
		}

	case "zset":
		// ZRangeWithScores with -1 returns all
		items, err := src.ZRangeWithScores(ctx, key, 0, -1).Result()
		if err != nil {
			log.Printf("Error reading zset %s: %v", key, err)
			return
		}
		if len(items) > 0 {
			pipe.Del(ctx, key)
			zMembers := make([]redis.Z, len(items))
			for i, item := range items {
				zMembers[i] = redis.Z{Score: item.Score, Member: item.Member}
			}
			pipe.ZAdd(ctx, key, zMembers...)
		}

	default:
		log.Printf("Skipping unsupported key type %s for key %s", keyType, key)
		return
	}

	// Restore TTL if it exists
	if ttl > 0 {
		pipe.PExpire(ctx, key, ttl)
	}

	_, err = pipe.Exec(ctx)
	if err != nil {
		log.Printf("Failed to write key %s: %v", key, err)
	}
}
