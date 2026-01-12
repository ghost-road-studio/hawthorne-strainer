import Config

config :hawthorne_strainer,
  name: :hawthorne_main,
  model_path: "config/model.conf"

import_config "#{config_env()}.exs"
