class CORSHandler < Kemal::Handler
  def call(env)
    if request_path_startswith env, ["/api"]
      env.response.headers["Access-Control-Allow-Origin"] = "*"
    end
    if env.request.path.ends_with?("jxl_dec.js")
      env.response.headers["Cache-Control"] = "max-age=604800"
    end
    if env.request.path.ends_with?("jxl_dec.wasm")
      env.response.headers["Cache-Control"] = "max-age=604800"
    end
    call_next env
  end
end
