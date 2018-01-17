package cache

import (
	"fmt"
	"strconv"
	"time"

	"github.com/inverse-inc/packetfence/go/coredns/core/dnsserver"
	"github.com/inverse-inc/packetfence/go/coredns/plugin"
	"github.com/inverse-inc/packetfence/go/coredns/plugin/pkg/cache"

	"github.com/inverse-inc/packetfence/go/caddy/caddy"
)

func init() {
	caddy.RegisterPlugin("cache", caddy.Plugin{
		ServerType: "dns",
		Action:     setup,
	})
}

func setup(c *caddy.Controller) error {
	ca, err := cacheParse(c)
	if err != nil {
		return plugin.Error("cache", err)
	}
	dnsserver.GetConfig(c).AddPlugin(func(next plugin.Handler) plugin.Handler {
		ca.Next = next
		return ca
	})

	// Export the capacity for the metrics. This only happens once, because this is a re-load change only.
	cacheCapacity.WithLabelValues(Success).Set(float64(ca.pcap))
	cacheCapacity.WithLabelValues(Denial).Set(float64(ca.ncap))

	return nil
}

func cacheParse(c *caddy.Controller) (*Cache, error) {

	ca := &Cache{pcap: defaultCap, ncap: defaultCap, pttl: maxTTL, nttl: maxNTTL, prefetch: 0, duration: 1 * time.Minute}

	for c.Next() {
		// cache [ttl] [zones..]
		origins := make([]string, len(c.ServerBlockKeys))
		copy(origins, c.ServerBlockKeys)
		args := c.RemainingArgs()

		if len(args) > 0 {
			// first args may be just a number, then it is the ttl, if not it is a zone
			ttl, err := strconv.Atoi(args[0])
			if err == nil {
				// Reserve 0 (and smaller for future things)
				if ttl <= 0 {
					return nil, fmt.Errorf("cache TTL can not be zero or negative: %d", ttl)
				}
				ca.pttl = time.Duration(ttl) * time.Second
				ca.nttl = time.Duration(ttl) * time.Second
				args = args[1:]
			}
			if len(args) > 0 {
				copy(origins, args)
			}
		}

		// Refinements? In an extra block.
		for c.NextBlock() {
			switch c.Val() {
			// first number is cap, second is an new ttl
			case Success:
				args := c.RemainingArgs()
				if len(args) == 0 {
					return nil, c.ArgErr()
				}
				pcap, err := strconv.Atoi(args[0])
				if err != nil {
					return nil, err
				}
				ca.pcap = pcap
				if len(args) > 1 {
					pttl, err := strconv.Atoi(args[1])
					if err != nil {
						return nil, err
					}
					// Reserve 0 (and smaller for future things)
					if pttl <= 0 {
						return nil, fmt.Errorf("cache TTL can not be zero or negative: %d", pttl)
					}
					ca.pttl = time.Duration(pttl) * time.Second
				}
			case Denial:
				args := c.RemainingArgs()
				if len(args) == 0 {
					return nil, c.ArgErr()
				}
				ncap, err := strconv.Atoi(args[0])
				if err != nil {
					return nil, err
				}
				ca.ncap = ncap
				if len(args) > 1 {
					nttl, err := strconv.Atoi(args[1])
					if err != nil {
						return nil, err
					}
					// Reserve 0 (and smaller for future things)
					if nttl <= 0 {
						return nil, fmt.Errorf("cache TTL can not be zero or negative: %d", nttl)
					}
					ca.nttl = time.Duration(nttl) * time.Second
				}
			case "prefetch":
				args := c.RemainingArgs()
				if len(args) == 0 || len(args) > 3 {
					return nil, c.ArgErr()
				}
				amount, err := strconv.Atoi(args[0])
				if err != nil {
					return nil, err
				}
				if amount < 0 {
					return nil, fmt.Errorf("prefetch amount should be positive: %d", amount)
				}
				ca.prefetch = amount

				ca.duration = 1 * time.Minute
				ca.percentage = 10
				if len(args) > 1 {
					dur, err := time.ParseDuration(args[1])
					if err != nil {
						return nil, err
					}
					ca.duration = dur
				}
				if len(args) > 2 {
					pct := args[2]
					if x := pct[len(pct)-1]; x != '%' {
						return nil, fmt.Errorf("last character of percentage should be `%%`, but is: %q", x)
					}
					pct = pct[:len(pct)-1]

					num, err := strconv.Atoi(pct)
					if err != nil {
						return nil, err
					}
					if num < 10 || num > 90 {
						return nil, fmt.Errorf("percentage should fall in range [10, 90]: %d", num)
					}
					ca.percentage = num
				}

			default:
				return nil, c.ArgErr()
			}
		}

		for i := range origins {
			origins[i] = plugin.Host(origins[i]).Normalize()
		}

		ca.Zones = origins

		ca.pcache = cache.New(ca.pcap)
		ca.ncache = cache.New(ca.ncap)

		return ca, nil
	}

	return nil, nil
}
