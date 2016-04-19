local conf_loader = require "kong.conf_loader"
local helpers = require "spec.helpers"

describe("Configuration loader", function()
  it("loads the defaults", function()
    local conf = assert(conf_loader())
    assert.is_string(conf.lua_package_path)
    assert.equal("auto", conf.nginx_worker_processes)
    assert.equal("0.0.0.0:8001", conf.admin_listen)
    assert.equal("0.0.0.0:8000", conf.proxy_listen)
    assert.equal("0.0.0.0:8443", conf.proxy_listen_ssl)
    assert.is_nil(conf.ssl_cert) -- check placeholder value
    assert.is_nil(conf.ssl_cert_key)
    assert.is_nil(getmetatable(conf))
  end)
  it("loads a given file, with higher precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    -- defaults
    assert.equal("on", conf.nginx_daemon)
    -- overrides
    assert.equal("1", conf.nginx_worker_processes)
    assert.equal("0.0.0.0:9001", conf.admin_listen)
    assert.equal("0.0.0.0:9000", conf.proxy_listen)
    assert.equal("0.0.0.0:9443", conf.proxy_listen_ssl)
    assert.is_nil(getmetatable(conf))
  end)
  it("preserves default properties if not in given file", function()
    local conf = assert(conf_loader(helpers.test_conf_path))
    assert.is_string(conf.lua_package_path) -- still there
  end)
  it("accepts custom params, with highest precedence", function()
    local conf = assert(conf_loader(helpers.test_conf_path, {
      admin_listen = "127.0.0.1:9001",
      nginx_worker_processes = "auto"
    }))
    -- defaults
    assert.equal("on", conf.nginx_daemon)
    -- overrides
    assert.equal("auto", conf.nginx_worker_processes)
    assert.equal("127.0.0.1:9001", conf.admin_listen)
    assert.equal("0.0.0.0:9000", conf.proxy_listen)
    assert.equal("0.0.0.0:9443", conf.proxy_listen_ssl)
    assert.is_nil(getmetatable(conf))
  end)
  it("strips extraneous properties (not in defaults)", function()
    local conf = assert(conf_loader(nil, {
      stub_property = "leave me alone"
    }))
    assert.is_nil(conf.stub_property)
  end)
  it("returns a plugins table", function()
    local constants = require "kong.constants"
    local conf = assert(conf_loader())
    assert.is_nil(conf.custom_plugins)
    assert.same(constants.PLUGINS_AVAILABLE, conf.plugins)
  end)
  it("loads custom plugins", function()
    local conf = assert(conf_loader(nil, {
      custom_plugins = "hello-world,my-plugin"
    }))
    assert.is_nil(conf.custom_plugins)
    assert.True(conf.plugins["hello-world"])
    assert.True(conf.plugins["my-plugin"])
  end)

  describe("inferences", function()
    it("infer booleans (on/off/true/false strings)", function()
      local conf = assert(conf_loader())
      assert.True(conf.dnsmasq)
      assert.equal("on", conf.nginx_daemon)
      assert.equal("on", conf.lua_code_cache)
      assert.True(conf.anonymous_reports)
      assert.False(conf.cassandra_ssl)
      assert.False(conf.cassandra_ssl_verify)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = true
      }))
      assert.True(conf.cassandra_ssl)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = "on"
      }))
      assert.True(conf.cassandra_ssl)

      conf = assert(conf_loader(nil, {
        cassandra_ssl = "true"
      }))
      assert.True(conf.cassandra_ssl)
    end)
    it("infer arrays (comma-separated strings)", function()
      local conf = assert(conf_loader())
      assert.same({"127.0.0.1"}, conf.cassandra_contact_points)
      assert.same({"dc1:2", "dc2:3"}, conf.cassandra_data_centers)
      assert.is_nil(getmetatable(conf.cassandra_contact_points))
      assert.is_nil(getmetatable(conf.cassandra_data_centers))
    end)
    it("infer ngx_boolean", function()
      local conf = assert(conf_loader(nil, {
        lua_code_cache = true
      }))
      assert.equal("on", conf.lua_code_cache)

      conf = assert(conf_loader(nil, {
        lua_code_cache = false
      }))
      assert.equal("off", conf.lua_code_cache)

      conf = assert(conf_loader(nil, {
        lua_code_cache = "off"
      }))
      assert.equal("off", conf.lua_code_cache)
    end)
  end)

  describe("validations", function()
    it("enforces properties types", function()
      local conf, err = conf_loader(nil, {
        lua_package_path = 123
      })
      assert.equal("lua_package_path is not a string: '123'", err)
      assert.is_nil(conf)
    end)
    it("enforces enums", function()
      local conf, err = conf_loader(nil, {
        database = "mysql"
      })
      assert.equal("database has an invalid value: 'mysql' (postgres, cassandra)", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        cassandra_consistency = "FOUR"
      })
      assert.equal("cassandra_consistency has an invalid value: 'FOUR'"
                 .." (ALL, EACH_QUORUM, QUORUM, LOCAL_QUORUM, ONE, TWO,"
                 .." THREE, LOCAL_ONE)", err)
      assert.is_nil(conf)
    end)
  end)

  describe("errors", function()
    it("returns inexistent file", function()
      local conf, err = conf_loader "inexistent"
      assert.equal("no file at: inexistent", err)
      assert.is_nil(conf)
    end)
    it("requires cert and key if SSL is enabled", function()
      local conf, err = conf_loader(nil, {
        ssl = true
      })
      assert.equal("ssl_cert required if SSL enabled", err)
      assert.is_nil(conf)

      conf, err = conf_loader(nil, {
        ssl = true,
        ssl_cert = "/path/cert.pem"
      })
      assert.equal("ssl_cert_key required if SSL enabled", err)
      assert.is_nil(conf)
    end)
    it("returns all errors in ret value #3", function()
      local conf, _, errors = conf_loader(nil, {
        ssl = true,
        cassandra_repl_strategy = "foo"
      })
      assert.equal(2, #errors)
      assert.is_nil(conf)
      assert.matches("cassandra_repl_strategy has", errors[1], nil, true)
      assert.matches("ssl_cert required", errors[2], nil, true)
    end)
  end)
end)
