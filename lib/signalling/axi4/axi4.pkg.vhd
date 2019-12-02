library ieee;
use ieee.std_logic_1164.all;

package axi4 is

	-------------------------------------------------------------------------------------
	-- address 	= 32 bits
	-- data 	= 64 bits
	-- length	=  4 bits
	-- id 		=  6 bits
	-------------------------------------------------------------------------------------
	
	type a32_d64_l4_id6_ms is record
		araddr		: std_logic_vector(31 downto 0);
		arburst		: std_logic_vector(1 downto 0);
		arcache		: std_logic_vector(3 downto 0);
		arid		: std_logic_vector(5 downto 0);
		arlen		: std_logic_vector(3 downto 0);
		arlock		: std_logic_vector(1 downto 0);
		arprot		: std_logic_vector(2 downto 0);
		arqos		: std_logic_vector(3 downto 0);
		arsize		: std_logic_vector(2 downto 0);
		arvalid		: std_logic;			
		awaddr		: std_logic_vector(31 downto 0);
		awburst		: std_logic_vector(1 downto 0);
		awcache		: std_logic_vector(3 downto 0);
		awid		: std_logic_vector(5 downto 0);
		awlen		: std_logic_vector(3 downto 0);
		awlock		: std_logic_vector(1 downto 0);
		awprot		: std_logic_vector(2 downto 0);
		awqos		: std_logic_vector(3 downto 0);
		awsize		: std_logic_vector(2 downto 0);
		awvalid		: std_logic;			
		bready		: std_logic;			
		rready		: std_logic;
		wdata		: std_logic_vector(63 downto 0);
		wid			: std_logic_vector(5 downto 0);
		wlast		: std_logic;	
		wstrb		: std_logic_vector(7 downto 0);
		wvalid		: std_logic;
	end record;
	 
	type a32_d64_l4_id6_sm is record
		arready		: std_logic;	
		awready		: std_logic;		
		bid			: std_logic_vector(5 downto 0);
		bresp		: std_logic_vector(1 downto 0);
		bvalid		: std_logic;
		rdata		: std_logic_vector(63 downto 0);
		rid			: std_logic_vector(5 downto 0);
		rlast		: std_logic;
		rresp		: std_logic_vector(1 downto 0);
		rvalid		: std_logic;
		wready		: std_logic;
	end record;

	type a32_d64_l4_id6 is record
		ms			: a32_d64_l4_id6_ms;
		sm			: a32_d64_l4_id6_sm;
	end record;

	constant a32_d64_l4_id6_ms_idle : a32_d64_l4_id6_ms :=
	(
		araddr		=> (others => '0'),
		arburst		=> (others => '0'),
		arcache		=> (others => '0'),
		arid		=> (others => '0'),
		arlen		=> (others => '0'),
		arlock		=> (others => '0'),
		arprot		=> (others => '0'),
		arqos		=> (others => '0'),
		arsize		=> (others => '0'),
		arvalid		=> '0',		
		awaddr		=> (others => '0'),
		awburst		=> (others => '0'),
		awcache		=> (others => '0'),
		awid		=> (others => '0'),
		awlen		=> (others => '0'),
		awlock		=> (others => '0'),
		awprot		=> (others => '0'),
		awqos		=> (others => '0'),
		awsize		=> (others => '0'),
		awvalid		=> '0',			
		bready		=> '0',			
		rready		=> '0',
		wdata		=> (others => '0'),
		wid			=> (others => '0'),
		wlast		=> '0',
		wstrb		=> (others => '0'),
		wvalid		=> '0'
	);
	
	constant a32_d64_l4_id6_sm_idle : a32_d64_l4_id6_sm := 
	(
		arready		=> '0',	
		awready		=> '0',		
		bid			=> (others => '0'),
		bresp		=> (others => '0'),
		bvalid		=> '0',
		rdata		=> (others => '0'),
		rid			=> (others => '0'),
		rlast		=> '0',
		rresp		=> (others => '0'),
		rvalid		=> '0',
		wready		=> '0'
	);
	
	constant a32_d64_l4_id6_idle : a32_d64_l4_id6 :=
	(
		ms			=> a32_d64_l4_id6_ms_idle,
		sm			=> a32_d64_l4_id6_sm_idle
	);
	
	-------------------------------------------------------------------------------------
	-- address 	= 32 bits
	-- data 	= 32 bits
	-- length	=  4 bits
	-- id 		=  6 bits
	-------------------------------------------------------------------------------------
	
	type a32_d32_l4_id6_ms is record
		araddr		: std_logic_vector(31 downto 0);
		arburst		: std_logic_vector(1 downto 0);
		arcache		: std_logic_vector(3 downto 0);
		arid		: std_logic_vector(5 downto 0);
		arlen		: std_logic_vector(3 downto 0);
		arlock		: std_logic_vector(1 downto 0);
		arprot		: std_logic_vector(2 downto 0);
		arqos		: std_logic_vector(3 downto 0);
		arsize		: std_logic_vector(2 downto 0);
		arvalid		: std_logic;			
		awaddr		: std_logic_vector(31 downto 0);
		awburst		: std_logic_vector(1 downto 0);
		awcache		: std_logic_vector(3 downto 0);
		awid		: std_logic_vector(5 downto 0);
		awlen		: std_logic_vector(3 downto 0);
		awlock		: std_logic_vector(1 downto 0);
		awprot		: std_logic_vector(2 downto 0);
		awqos		: std_logic_vector(3 downto 0);
		awsize		: std_logic_vector(2 downto 0);
		awvalid		: std_logic;			
		bready		: std_logic;			
		rready		: std_logic;
		wdata		: std_logic_vector(31 downto 0);
		wid			: std_logic_vector(5 downto 0);
		wlast		: std_logic;	
		wstrb		: std_logic_vector(3 downto 0);
		wvalid		: std_logic;
	end record;
	 
	type a32_d32_l4_id6_sm is record
		arready		: std_logic;	
		awready		: std_logic;		
		bid			: std_logic_vector(5 downto 0);
		bresp		: std_logic_vector(1 downto 0);
		bvalid		: std_logic;
		rdata		: std_logic_vector(31 downto 0);
		rid			: std_logic_vector(5 downto 0);
		rlast		: std_logic;
		rresp		: std_logic_vector(1 downto 0);
		rvalid		: std_logic;
		wready		: std_logic;
	end record;

	type a32_d32_l4_id6 is record
		ms			: a32_d64_l4_id6_ms;
		sm			: a32_d64_l4_id6_sm;
	end record;

	constant a32_d32_l4_id6_ms_idle : a32_d32_l4_id6_ms :=
	(
		araddr		=> (others => '0'),
		arburst		=> (others => '0'),
		arcache		=> (others => '0'),
		arid		=> (others => '0'),
		arlen		=> (others => '0'),
		arlock		=> (others => '0'),
		arprot		=> (others => '0'),
		arqos		=> (others => '0'),
		arsize		=> (others => '0'),
		arvalid		=> '0',		
		awaddr		=> (others => '0'),
		awburst		=> (others => '0'),
		awcache		=> (others => '0'),
		awid		=> (others => '0'),
		awlen		=> (others => '0'),
		awlock		=> (others => '0'),
		awprot		=> (others => '0'),
		awqos		=> (others => '0'),
		awsize		=> (others => '0'),
		awvalid		=> '0',			
		bready		=> '0',			
		rready		=> '0',
		wdata		=> (others => '0'),
		wid			=> (others => '0'),
		wlast		=> '0',
		wstrb		=> (others => '0'),
		wvalid		=> '0'
	);
	
	constant a32_d32_l4_id6_sm_idle : a32_d32_l4_id6_sm := 
	(
		arready		=> '0',	
		awready		=> '0',		
		bid			=> (others => '0'),
		bresp		=> (others => '0'),
		bvalid		=> '0',
		rdata		=> (others => '0'),
		rid			=> (others => '0'),
		rlast		=> '0',
		rresp		=> (others => '0'),
		rvalid		=> '0',
		wready		=> '0'
	);
	
	constant a32_d32_l4_id6_idle : a32_d32_l4_id6 :=
	(
		ms			=> a32_d64_l4_id6_ms_idle,
		sm			=> a32_d64_l4_id6_sm_idle
	);

end package;
