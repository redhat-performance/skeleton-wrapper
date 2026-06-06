import pydantic
import datetime

from enum import Enum

class Benchmark(Enum):
	PING_INLINE = "PING_INLINE"
	PING_MBULK ="PING_MBULK"
	SET = "SET"
	GET = "GET"
	INCR = "INCR"
	LPUSH = "LPUSH"
	RPUSH = "RPUSH"
	LPOP = "LPOP"
	RPOP = "RPOP"
	SADD = "SADD"
	HSET = "HSET"
	SPOP = "SPOP"
	ZADD = "ZADD"
	ZPOPMIN = "ZPOPMIN"
	LPUSH_needed_to_benchmark_LRANGE = "LPUSH_needed_to_benchmark_LRANGE"
	LRANGE_100_first_100_elements = "LRANGE_100_first_100_elements"
	LRANGE_300_first_300_elements = "LRANGE_300_first_300_elements"
	LRANGE_500_first_500_elements = "LRANGE_500_first_500_elements"
	LRANGE_600_first_600_elements = "LRANGE_600_first_600_elements"
	MSET_10_keys = "MSET_10_keys"
	XADD = "XADD"

class valkey_Results (pydantic.BaseModel):
    Test: Benchmark
    RPS: float = pydantic.Field(gt=0, allow_inf_nan=False)
    Start_Date: datetime.datetime
    End_Date: datetime.datetime
