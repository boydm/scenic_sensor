# Scenic.Sensor

`Scenic.Sensor` is a combination pub/sub server and data cache for sensors. It is intended to be the interface between sensors and Scenic scenes, although it has no dependencies on Scenic and can be used in other applications.

## Installation

`Scenic.Sensor` can be installed by adding `:scenic_sensor` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:scenic_sensor, "~> 0.7.0"}
  ]
end
```

## Startup

In order to use `Scenic.Sensor`, you must first add it to your supervision tree. It should be ordered in the tree so that it has a chance to initialize before other processes start making calls to it.

      def start(_type, _args) do
        import Supervisor.Spec, warn: false

        opts = [strategy: :one_for_one, name: ScenicExample]
        children = [
          {Scenic.Sensor, nil},
          ...
        ]
        Supervisor.start_link(children, strategy: :one_for_one)
      end


## Why Scenic.Sensor

Sensors and scenes often need to communicate, but tend to operate on different timelines.

Some sensors update fairly slowly or don't behave well when asked to get data at random times by multiple clients. `Scenic.Sensor` lets you create a GenServer that collects data from a sensor in a well-behaved manner, yet is able to serve that data on demand or by subscription to many clients.


## Registering Sensors

Before a process can start publishing data from a sensor, it must register that sensor with `Scenic.Sensor`. This both prevents other processes from stepping on that data and alerts any subscribing processes that the sensor is coming online.

      Scenic.Sensor.register( :sensor_id, version, description )

The `:sensor_id` parameter must be an atom that names the sensor. Subscribers will look for data from this sensor through that id.

The `version` and `description` paramters are bitstrings that describe this sensor. `Scenic.Sensor` itself does not process these values, but passes them to the listeners when the sensor comes online or when the sensors are listed.

Sensors can also unregister if they are no longer available.

      Scenic.Sensor.unregister( :sensor_id )

Simply exiting the sensor does also cleans up its registration.


## Publishing Data

When a sensor process publishes data, two things happen. First, that data is cached in an `:ets` table so that future requests for that data from scenes happen quickly and don't need to bother the sensor. Second, any processes that have subscribed to that sensor are sent a message containing the new data.

      Scenic.Sensor.publish( :sensor_id, sensor_value )

The `:sensor_id` parameter must be an atom that was previously registered by calling process.

The `sensor_value` parameter can be anything that makes sense for the sensor.


## Subscribing to a sensor

Scenes (or any other process) can subscribe to a sensor. They will receive messages when the sensor updates its data, comes online, or goes away.

      Scenic.Sensor.subscribe( :sensor_id )

The `:sensor_id` parameter is the atom registered for the sensor.

The subscribing process will then start receiving messages that can be handled with `handle_info/2`

event | message
--- | ---
data | `{:sensor, :data, {:sensor_id, data, timestamp}}` 
registered | `{:sensor, :registered, {:sensor_id, version, description}}` 
unregistered | `{:sensor, :unregistered, :sensor_id}` 

Scenes can also unsubscribe if they are no longer interested in updates.

      Scenic.Sensor.unsubscribe( :sensor_id )

## Other functions

Any process can get data from a sensor on demand, whether or not it is a subscriber.

      Scenic.Sensor.get( :sensor_id )
      >> {:ok, data}

Any process can list the currently registered sensors

      Scenic.Sensor.list()
      >> [{:sensor_id, version, description, pid}]

