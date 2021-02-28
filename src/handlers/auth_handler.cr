require "kemal"
require "../storage"
require "../util/*"

class AuthHandler < Kemal::Handler
  # Some of the code is copied form kemalcr/kemal-basic-auth on GitHub

  BASIC        = "Basic"
  AUTH         = "Authorization"
  AUTH_MESSAGE = "Could not verify your access level for that URL.\n" \
                 "You have to login with proper credentials"
  HEADER_LOGIN_REQUIRED = "Basic realm=\"Login Required\""

  def require_basic_auth(env)
    env.response.status_code = 401
    env.response.headers["WWW-Authenticate"] = HEADER_LOGIN_REQUIRED
    env.response.print AUTH_MESSAGE
  end

  def require_auth(env)
    env.session.string "callback", env.request.path
    redirect env, "/login"
  end

  def validate_token(env)
    token = env.session.string? "token"
    !token.nil? && Storage.default.verify_token token
  end

  def validate_token_admin(env)
    token = env.session.string? "token"
    !token.nil? && Storage.default.verify_admin token
  end

  def validate_auth_header(env)
    if env.request.headers[AUTH]?
      if value = env.request.headers[AUTH]
        if value.size > 0 && value.starts_with?(BASIC)
          token = verify_user value
          return false if token.nil?

          env.session.string "token", token
          return true
        end
      end
    end
    false
  end

  def verify_user(value)
    username, password = Base64.decode_string(value[BASIC.size + 1..-1])
      .split(":")
    Storage.default.verify_user username, password
  end

  def call(env)
    # Skip all authentication if requesting /login, /logout, or a static file
    if request_path_startswith(env, ["/login", "/logout"]) ||
       requesting_static_file env
      return call_next(env)
    end

    # Check user is logged in
    if validate_token env
      # Skip if the request has a valid token
    elsif Config.current.disable_login
      # Check default username if login is disabled
      unless Storage.default.username_exists Config.current.default_username
        Logger.warn "Default username #{Config.current.default_username} " \
                    "does not exist"
        return require_auth env
      end
    elsif !Config.current.auth_proxy_header_name.empty?
      # Check auth proxy if present
      username = env.request.headers[Config.current.auth_proxy_header_name]?
      unless username && Storage.default.username_exists username
        Logger.warn "Header #{Config.current.auth_proxy_header_name} unset " \
                    "or is not a valid username"
        return require_auth env
      end
    elsif request_path_startswith env, ["/opds"]
      # Check auth header if requesting an opds page
      unless validate_auth_header env
        return require_basic_auth env
      end
    else
      return require_auth env
    end

    # Check admin access when requesting an admin page
    if request_path_startswith env, %w(/admin /api/admin /download)
      unless is_admin? env
        env.response.status_code = 403
        return send_error_page "HTTP 403: You are not authorized to visit " \
                               "#{env.request.path}"
      end
    end

    # Let the request go through if it passes the above checks
    call_next env
  end
end
