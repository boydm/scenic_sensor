#
#  Created by Boyd Multerer on August 20, 2018.
#  Copyright © 2018 Kry10 Industries. All rights reserved.
#
# Centralized sensor data pub-sub with cache

defmodule Scenic.Sensor do
  use GenServer

  @moduledoc """

  A combination pub/sub server and data cache for sensors. It is intended to be the interface between
  sensors (or other data sources) and Scenic scenes, although it has no dependencies on Scenic and can
  be used in other applications.

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

  The subscribing process with then start receiving messages that can be handled with `handle_info/2`

  event | message
  --- | ---
  data | `{:sensor, :data, {:sensor_id, data, timestamp}}` 
  registered | `{:sensor, :registered, {:sensor_id, version, description}}` 
  unregistered | `{:sensor, :unregistered, :sensor_id}` 

  Scenes can also unsubscribe if they are no longer interested in updates.

        Scenic.Sensor.unsubscribe( :sensor_id )

  """

  # ets table names
  @sensor_table __MODULE__
  @name __MODULE__

  # ============================================================================
  # client api

  # --------------------------------------------------------
  @doc """
  Retrieve the cached data for a named sensor.

  This data is pulled from an `:ets` table and does not put load on the sensor itself.

  ## Parameters
  * `sensor_id` an atom that is registered to a sensor.

  ## Return Value

        {:ok, {sensor_id, data, timestamp}}

  * `sensor_id` is the atom representing the sensor.
  * `data` is whatever data the sensor last published.
  * `timestamp` is the time - from `:os.system_time(:micro_seconds)` - the last data was published.

  If the sensor is either not registered, or has not yet published any data, get returns

        {:error, :no_data} 
  """

  @spec get(sensor_id :: atom) :: {:ok, any} | {:error, :no_data}
  def get(sensor_id) when is_atom(sensor_id) do
    case :ets.lookup(@sensor_table, sensor_id) do
      [data] ->
        {:ok, data}

      # no data
      _ ->
        {:error, :no_data}
    end
  end

  # --------------------------------------------------------
  @doc """
  List the registered sensors.

  ## Return Value

  `list/0` returns a list of registered sensors

        [{sensor_id, version, description, pid}]

  * `sensor_id` is the atom representing the sensor.
  * `version` is the version string supplied by the sensor during registration.
  * `description` is the description string supplied by the sensor during registration.
  * `pid` is the pid of the sensor process.
  """
  @spec list() :: list
  def list() do
    :ets.match(@sensor_table, {{:registration, :"$1"}, :"$2", :"$3", :"$4"})
    |> Enum.map(fn [key, ver, des, pid] -> {key, ver, des, pid} end)
  end

  # --------------------------------------------------------
  @doc """
  Publish a data point from a sensor.

  When a sensor uses `publish/2` to publish data, that data is recorded in the
  cache and a
        {:sensor, :data, {:sensor_id, data, timestamp}}
  message is sent to each subsciber. The timestamp is the current time in microsecods as returned
  from `:os.system_time(:micro_seconds)`.

  ## Parameters
  * `sensor_id` an atom that is registered to a sensor.
  * `data` the data to publish.

  ## Return Value

  On success, returns `:ok`

  It returns `{:error, :not_registered}` if the caller is not the
  registered process for the sensor.
  """
  @spec publish(sensor_id :: atom, data :: any) :: :ok
  def publish(sensor_id, data) when is_atom(sensor_id) do
    timestamp = :os.system_time(:micro_seconds)
    pid = self()

    # enforce that this is coming from the registered sensor pid
    case :ets.lookup(@sensor_table, {:registration, sensor_id}) do
      [{_, _, _, ^pid}] ->
        send(@name, {:put_data, sensor_id, data, timestamp})
        :ok

      # no data
      _ ->
        {:error, :not_registered}
    end
  end

  # --------------------------------------------------------
  @doc """
  Subscribe the calling process to receive events about a sensor.

  The events the caller will start receiving about a sensor are:

  event | message
  --- | ---
  data | `{:sensor, :data, {:sensor_id, data, timestamp}}` 
  registered | `{:sensor, :registered, {:sensor_id, version, description}}` 
  unregistered | `{:sensor, :unregistered, :sensor_id}` 

  ## Parameters
  * `sensor_id` an atom that is registered to a sensor.

  ## Return Value

  On success, returns `:ok`
  """
  @spec subscribe(sensor_id :: atom) :: :ok
  def subscribe(sensor_id) when is_atom(sensor_id) do
    GenServer.call(@name, {:subscribe, sensor_id, self()})
  end

  # --------------------------------------------------------
  @doc """
  Unsubscribe the calling process from receive events about a sensor.

  The caller will stop receiving events about a sensor

  ## Parameters
  * `sensor_id` an atom that is registered to a sensor.

  ## Return Value

  Returns `:ok`
  """
  @spec unsubscribe(sensor_id :: atom) :: :ok
  def unsubscribe(sensor_id) when is_atom(sensor_id) do
    send(@name, {:unsubscribe, sensor_id, self()})
    :ok
  end

  # --------------------------------------------------------
  @doc """
  Register the calling process as a data source for a sensor.

  ## Parameters
  * `sensor_id` the sensor it being registered.
  * `version` the sensor version string.
  * `description` a sensor description string.

  ## Return Value

  On success, returns `{:ok, sensor_id}`

  If `sensor_id` is already registered to another process, it returns

      {:error, :already_registered}
  """
  @spec register(
          sensor_id :: atom,
          version :: String.t(),
          description :: String.t()
        ) :: {:ok, atom} | {:error, :already_registered}
  def register(sensor_id, version, description)
      when is_atom(sensor_id) and is_bitstring(version) and is_bitstring(description) do
    GenServer.call(
      @name,
      {:register, sensor_id, version, description, self()}
    )
  end

  # --------------------------------------------------------
  @doc """
  Unregister the calling process as a data source for a sensor.

  ## Parameters
  * `sensor_id` the sensor it being registered.

  ## Return Value

  Returns `:ok`
  """
  @spec unregister(sensor_id :: atom) :: :ok
  def unregister(sensor_id) when is_atom(sensor_id) do
    send(@name, {:unregister, sensor_id, self()})
    :ok
  end

  # ============================================================================
  # internal api

  # --------------------------------------------------------
  @doc false
  def start_link(_) do
    GenServer.start_link(__MODULE__, :ok, name: @name)
  end

  # --------------------------------------------------------
  @doc false
  def init(:ok) do
    # set up the initial state
    state = %{
      data_table_id: :ets.new(@sensor_table, [:named_table]),
      subs_id: %{},
      subs_pid: %{}
    }

    # trap exits so we don't just crash when a subscriber goes away
    Process.flag(:trap_exit, true)

    {:ok, state}
  end

  # ============================================================================

  # --------------------------------------------------------
  # a sensor (or whatever) is putting data
  @doc false
  # the client api enforced the pid check
  # yes, you could get around that by sending this message directly
  # not best-practice, but is an escape valve.
  # timestamp should be from :os.system_time(:micro_seconds)
  def handle_info({:put_data, sensor_id, data, timestamp}, state) do
    :ets.insert(@sensor_table, {sensor_id, data, timestamp})
    send_subs(sensor_id, :data, {sensor_id, data, timestamp}, state)
    {:noreply, state}
  end

  # --------------------------------------------------------
  @doc false
  def handle_info({:unsubscribe, sensor_id, pid}, state) do
    {:noreply, unsubscribe(pid, sensor_id, state)}
  end

  # ============================================================================
  # handle linked processes going down

  # --------------------------------------------------------
  def handle_info({:EXIT, pid, _reason}, state) do
    # unsubscribe everything this pid was listening to
    state = do_unsubscribe(pid, :all, state)

    # if this pid was registered as a sensor, unregister it
    :ets.match(@sensor_table, {{:registration, :"$1"}, :_, :_, pid})
    |> Enum.each(fn [id] -> do_unregister(id, pid, state) end)

    {:noreply, state}
  end

  # --------------------------------------------------------
  @doc false
  def handle_info({:unregister, sensor_id, pid}, state) do
    do_unregister(sensor_id, pid, state)
    {:noreply, state}
  end

  # ============================================================================
  # CALLs - mostly for postive confirmation of sign-up style things

  # --------------------------------------------------------
  @doc false
  def handle_call({:subscribe, sensor_id, pid}, _from, state) do
    {reply, state} = do_subscribe(pid, sensor_id, state)

    # send the already-set value if one is set
    case get(sensor_id) do
      {:ok, data} -> send_msg(pid, :data, data)
      _ -> :ok
    end

    {:reply, reply, state}
  end

  # --------------------------------------------------------
  @doc false
  # handle sensor registration
  def handle_call({:register, sensor_id, version, description, pid}, _from, state) do
    key = {:registration, sensor_id}

    {reply, state} =
      case :ets.lookup(@sensor_table, key) do
        # registered to pid - ok to change
        [{_, _, _, ^pid}] ->
          do_register(pid, sensor_id, version, description, state)

        # previously crashed
        [{_, _, _, nil}] ->
          do_register(pid, sensor_id, version, description, state)

        # registered to other. fail
        [_] ->
          {{:error, :already_registered}, state}

        [] ->
          do_register(pid, sensor_id, version, description, state)
      end

    {:reply, reply, state}
  end

  # ============================================================================
  # handle sensor registrations

  # --------------------------------------------------------
  defp do_register(pid, sensor_id, version, description, state) do
    key = {:registration, sensor_id}
    :ets.insert(@sensor_table, {key, version, description, pid})
    # link the sensor
    Process.link(pid)
    # alert the subscribers
    send_subs(sensor_id, :registered, {sensor_id, version, description}, state)
    # reply is sent back to the sensor
    {{:ok, sensor_id}, state}
  end

  # --------------------------------------------------------
  defp do_unregister(sensor_id, pid, state) do
    reg_key = {:registration, sensor_id}

    # first, get the registration and confirm this pid is registered
    case :ets.lookup(@sensor_table, reg_key) do
      [{_, _, _, ^pid}] ->
        # alert the subscribers
        send_subs(sensor_id, :unregistered, sensor_id, state)

        # delete the table entries
        :ets.delete(@sensor_table, reg_key)
        :ets.delete(@sensor_table, sensor_id)

        unlink_pid(pid, state)
        :ok

      # no registered. do nothing
      _ ->
        :ok
    end
  end

  # ============================================================================
  # handle client subscriptions

  # --------------------------------------------------------
  @spec do_subscribe(pid :: GenServer.server(), sensor_id :: atom, state :: map) :: any
  defp do_subscribe(pid, sensor_id, %{subs_id: subs_id, subs_pid: subs_pid} = state) do
    # record the subscription
    subs_id =
      Map.put(
        subs_id,
        sensor_id,
        [pid | Map.get(subs_id, sensor_id, [])] |> Enum.uniq()
      )

    subs_pid =
      Map.put(
        subs_pid,
        pid,
        [sensor_id | Map.get(subs_pid, pid, [])] |> Enum.uniq()
      )

    # make sure the subscriber is linked
    Process.link(pid)

    {:ok, %{state | subs_id: subs_id, subs_pid: subs_pid}}
  end

  # --------------------------------------------------------
  @spec do_unsubscribe(pid :: GenServer.server(), sensor_id :: atom, state :: map) :: any
  defp do_unsubscribe(pid, :all, %{subs_pid: subs_pid} = state) do
    Map.get(subs_pid, pid, [])
    |> Enum.reduce(state, &unsubscribe(pid, &1, &2))
  end

  # --------------------------------------------------------
  defp unsubscribe(pid, sensor_id, %{subs_id: subs_id, subs_pid: subs_pid} = state) do
    # clean up the subs for a given sensor_id
    subs_by_id =
      Map.get(subs_id, sensor_id, [])
      |> Enum.reject(fn sub_pid -> sub_pid == pid end)

    subs_id = Map.put(subs_id, sensor_id, subs_by_id)

    # part two
    subs_by_pid =
      Map.get(subs_pid, pid, [])
      |> Enum.reject(fn sub_id -> sub_id == sensor_id end)

    subs_pid = Map.put(subs_pid, pid, subs_by_pid)

    state = %{state | subs_id: subs_id, subs_pid: subs_pid}

    # if pid no longer subscribed to anything, then some further cleanup
    state =
      case subs_by_pid do
        [] ->
          {_, state} = pop_in(state, [:subs_pid, pid])
          state

        _ ->
          state
      end

    # if sensor has no subscribers, then some further cleanup
    state =
      case subs_by_id do
        [] ->
          {_, state} = pop_in(state, [:subs_id, sensor_id])
          state

        _ ->
          state
      end

    # does the right thing. only unlinks if no longer subscribing
    # to anything and is not a sensor
    unlink_pid(pid, state)

    state
  end

  # --------------------------------------------------------
  @spec send_subs(sensor_id :: atom, verb :: atom, msg :: any, state :: map) :: any
  defp send_subs(sensor_id, verb, msg, %{subs_id: subs_id}) do
    Map.get(subs_id, sensor_id, [])
    |> Enum.each(&send_msg(&1, verb, msg))
  end

  # --------------------------------------------------------
  @spec send_msg(pid :: GenServer.server(), verb :: atom, msg :: any) :: any
  defp send_msg(pid, verb, msg) do
    send(pid, {:sensor, verb, msg})
  end

  # --------------------------------------------------------
  # only unlink a pid if it is not a registered sensor AND it
  # has no subscriptions. return the state
  defp unlink_pid(pid, %{subs_pid: subs_pid}) do
    no_subs =
      case subs_pid[pid] do
        nil -> true
        [] -> true
        _ -> false
      end

    not_sensor =
      case :ets.match(@sensor_table, {{:registration, :"$1"}, :_, :_, pid}) do
        [] -> true
        _ -> false
      end

    if no_subs && not_sensor do
      Process.unlink(pid)
    end
  end
end
