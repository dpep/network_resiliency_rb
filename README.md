NetworkResiliency
======
![Gem](https://img.shields.io/gem/dt/network_resiliency?style=plastic)
[![codecov](https://codecov.io/gh/dpep/network_resiliency_rb/branch/main/graph/badge.svg)](https://codecov.io/gh/dpep/network_resiliency_rb)

Making network requests more resilient
- waste less time on failures by using dynamic, granular timeouts and deadeline propagation
- reduce errors by automatically retrying idempotent calls
- observe every network connection and request


```ruby
require "network_resiliency"

NetworkResiliency.configure do |conf|
  conf.statsd = Datadog::Statsd.new
end

Redis.new.ping
```


----
## Contributing

Yes please  :)

1. Fork it
1. Create your feature branch (`git checkout -b my-feature`)
1. Ensure the tests pass (`bundle exec rspec`)
1. Commit your changes (`git commit -am 'awesome new feature'`)
1. Push your branch (`git push origin my-feature`)
1. Create a Pull Request



----
### Inspired by

https://github.com/lostisland/faraday-retry/blob/main/lib/faraday/retry/middleware.rb

https://github.com/ankane/the-ultimate-guide-to-ruby-timeouts


https://reprep.io/writings/20220326_timeouts_deadline_propagation.html

https://grpc.io/blog/deadlines
