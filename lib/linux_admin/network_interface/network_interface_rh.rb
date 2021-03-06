require 'ipaddr'
require 'pathname'

module LinuxAdmin
  class NetworkInterfaceRH < NetworkInterface
    IFACE_DIR = "/etc/sysconfig/network-scripts"

    # @return [Hash<String, String>] Key value mappings in the interface file
    attr_reader :interface_config

    # @param interface [String] Name of the network interface to manage
    def initialize(interface)
      @interface_file = Pathname.new(IFACE_DIR).join("ifcfg-#{interface}")
      raise MissingConfigurationFileError unless File.exist?(@interface_file)
      super
      parse_conf
    end

    # Parses the interface configuration file into the @interface_config hash
    def parse_conf
      @interface_config = {}

      File.foreach(@interface_file) do |line|
        next if line =~ /^\s*#/

        key, value = line.split('=').collect(&:strip)
        @interface_config[key] = value
      end
      @interface_config["NM_CONTROLLED"] = "no"
    end

    # Set the IPv4 address for this interface
    #
    # @param address [String]
    # @raise ArgumentError if the address is not formatted properly
    def address=(address)
      validate_ip(address)
      @interface_config["BOOTPROTO"] = "static"
      @interface_config["IPADDR"]    = address
    end

    # Set the IPv4 gateway address for this interface
    #
    # @param address [String]
    # @raise ArgumentError if the address is not formatted properly
    def gateway=(address)
      validate_ip(address)
      @interface_config["GATEWAY"] = address
    end

    # Set the IPv4 sub-net mask for this interface
    #
    # @param mask [String]
    # @raise ArgumentError if the mask is not formatted properly
    def netmask=(mask)
      validate_ip(mask)
      @interface_config["NETMASK"] = mask
    end

    # Sets one or both DNS servers for this network interface
    #
    # @param servers [Array<String>] The DNS servers
    def dns=(*servers)
      server1, server2 = servers.flatten
      @interface_config["DNS1"] = server1
      @interface_config["DNS2"] = server2 if server2
    end

    # Sets the search domain list for this network interface
    #
    # @param domains [Array<String>] the list of search domains
    def search_order=(*domains)
      @interface_config["DOMAIN"] = "\"#{domains.flatten.join(' ')}\""
    end

    # Set up the interface to use DHCP
    # Removes any previously set static networking information
    def enable_dhcp
      @interface_config["BOOTPROTO"] = "dhcp"
      @interface_config.delete("IPADDR")
      @interface_config.delete("NETMASK")
      @interface_config.delete("GATEWAY")
      @interface_config.delete("PREFIX")
      @interface_config.delete("DNS1")
      @interface_config.delete("DNS2")
      @interface_config.delete("DOMAIN")
    end

    # Applies the given static network configuration to the interface
    #
    # @param ip [String] IPv4 address
    # @param mask [String] subnet mask
    # @param gw [String] gateway address
    # @param dns [Array<String>] list of dns servers
    # @param search [Array<String>] list of search domains
    # @return [Boolean] true on success, false otherwise
    # @raise ArgumentError if an IP is not formatted properly
    def apply_static(ip, mask, gw, dns, search = nil)
      self.address      = ip
      self.netmask      = mask
      self.gateway      = gw
      self.dns          = dns
      self.search_order = search if search
      save
    end

    # Writes the contents of @interface_config to @interface_file as `key`=`value` pairs
    # and resets the interface
    #
    # @return [Boolean] true if the interface was successfully brought up with the
    #   new configuration, false otherwise
    def save
      old_contents = File.read(@interface_file)

      return false unless stop

      File.write(@interface_file, @interface_config.delete_blanks.collect { |k, v| "#{k}=#{v}" }.join("\n"))

      unless start
        File.write(@interface_file, old_contents)
        start
        return false
      end

      true
    end

    private

    # Validate that the given address is formatted correctly
    #
    # @param ip [String]
    # @raise ArgumentError if the address is not correctly formatted
    def validate_ip(ip)
      IPAddr.new(ip)
    rescue ArgumentError
      raise ArgumentError, "#{ip} is not a valid IPv4 or IPv6 address"
    end
  end
end
