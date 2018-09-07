defmodule ScenicSensor.MixProject do
  use Mix.Project

  @version "0.7.0"

  def project do
    [
      app: :scenic_sensor,
      version: @version,
      elixir: "~> 1.7",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      docs: [
        main: "Scenic.Sensor"
        # source_ref: "v#{@version}",
        # source_url:≈ "https://github.com/boydm/scenic",
        # homepage_url: "http://kry10.com",
      ],
      description: description()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      # Docs dependencies
      {:ex_doc, ">= 0.0.0", only: [:dev, :docs]},
      {:dialyxir, "~> 0.5", only: :dev, runtime: false}
    ]
  end

  defp description() do
    """
    Scenic.Sensor - Sensor Pub/Sub Cache
    """
  end
end
