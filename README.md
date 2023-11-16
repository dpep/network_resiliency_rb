NetworkResiliency
======
![Gem](https://img.shields.io/gem/dt/network_resiliency?style=plastic)
[![codecov](https://codecov.io/gh/dpep/network_resiliency_rb/branch/main/graph/badge.svg)](https://codecov.io/gh/dpep/network_resiliency_rb)

Making network requests more resilient to error.
- less errors, by retrying
- less time, by setting granular timeouts


```ruby
require "network_resiliency"

NetworkResiliency.configure do |conf|
  conf.statsd = Datadog::Statsd.new

  # patch Redis instances
  conf.patch :redis
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
