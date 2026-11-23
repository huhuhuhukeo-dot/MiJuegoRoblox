--[[
	RateLimiter
	Token bucket per key (usually a Player). Pure logic: `now` can be injected
	for unit tests.
]]

local RateLimiter = {}
RateLimiter.__index = RateLimiter

function RateLimiter.new(rate: number, burst: number)
	assert(rate > 0 and burst >= 1, "RateLimiter: invalid parameters")
	return setmetatable({
		_rate = rate,
		_burst = burst,
		_buckets = setmetatable({}, { __mode = "k" }),
	}, RateLimiter)
end

-- Consumes one token. Returns true if the action is allowed.
function RateLimiter:Check(key: any, now: number?): boolean
	local t = now or os.clock()
	local bucket = self._buckets[key]
	if bucket == nil then
		bucket = { tokens = self._burst, last = t }
		self._buckets[key] = bucket
	end
	local elapsed = math.max(0, t - bucket.last)
	bucket.tokens = math.min(self._burst, bucket.tokens + elapsed * self._rate)
	bucket.last = t
	if bucket.tokens >= 1 then
		bucket.tokens -= 1
		return true
	end
	return false
end

function RateLimiter:Remove(key: any)
	self._buckets[key] = nil
end

return RateLimiter
