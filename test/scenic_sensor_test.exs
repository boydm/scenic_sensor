#
#  Created by Boyd Multerer on August 22, 2018.
#  Copyright © 2018 Kry10 Industries. All rights reserved.
#

#==============================================================================
defmodule Scenic.SensorTest do
  use ExUnit.Case, async: false
  doctest Scenic.Sensor

  alias Scenic.Sensor

  @table          Scenic.Sensor

  #--------------------------------------------------------
  setup do
    {:ok, svc} = Sensor.start_link( nil )
    on_exit fn -> Process.exit( svc, :normal ) end
    %{svc: svc}
  end

  #============================================================================
  # integration style tests

  test "integration - subscribe, register, publish, unregister" do
    # subscribe
    :ok = Sensor.subscribe( :abc )

    # register
    assert Sensor.list == []
    {:ok, :abc} = Sensor.register(:abc,"v","d")
    assert Sensor.list == [{:abc,"v","d",self()}]

    # confirm registration message was received
    assert_receive( {:sensor, :registered, {:abc, "v", "d"}} )
    # confirm no value was sent (none set)
    refute_receive( {:sensor, :data, _} )

    # send some data
    :ok = Sensor.publish(:abc,123)
    # confirm a data message was sent
    assert_receive( {:sensor, :data, {:abc, 123, timestamp}} )
    assert is_integer( timestamp )
    [{:abc,123,^timestamp}] = :ets.lookup(@table, :abc)

    # unregister the sensor
    refute_receive( {:sensor, :unregistered, :abc} )
    :ok = Sensor.unregister(:abc)
    assert_receive( {:sensor, :unregistered, :abc} )

    # should now fail to publish new data
    assert Sensor.publish(:abc,456) == {:error, :not_registered}
    refute_receive( {:sensor, :data, {:abc, 456, _}} )

    # confirm the table is empty
    assert :ets.lookup(@table, :abc) == []
    assert :ets.lookup(@table, {:registration, :abc}) == []
  end

  test "integration - register, publish, subscribe, unsubscribe, publish" do
    # register
    assert Sensor.list == []
    {:ok, :abc} = Sensor.register(:abc,"v","d")
    assert Sensor.list == [{:abc,"v","d",self()}]

    # publish some data
    :ok = Sensor.publish( :abc, 123 )
    # confirm a data message was not sent
    refute_receive( {:sensor, :data, _} )
    # confirm it is in the table
    [{:abc,123,timestamp}] = :ets.lookup(@table, :abc)

    # subscribe
    :ok = Sensor.subscribe( :abc )
    # confirm the previous data was sent
    assert_receive( {:sensor, :data, {:abc, 123, ^timestamp}} )

    # publish some more data
    :ok = Sensor.publish(:abc,456)
    # confirm a data message was sent
    # confirm the previous data was sent
    assert_receive( {:sensor, :data, {:abc, 456, timestamp2}} )
    refute timestamp == timestamp2

    # unregister the sensor
    refute_receive( {:sensor, :unregistered, :abc} )
    :ok = Sensor.unregister(:abc)
    assert_receive( {:sensor, :unregistered, :abc} )

    # should now fail to publish new data
    assert Sensor.publish(:abc,789) == {:error, :not_registered}
    refute_receive( {:sensor, :data, {:abc, 456, _}} )
  end

end