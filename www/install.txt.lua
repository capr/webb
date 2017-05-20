
local function pass(...)
	print_queries = false
	return ...
end
local function pq(sql, ...)
	print_queries = true
	return pass(query(sql, ...))
end

--ddl vocabulary -------------------------------------------------------------

local nodrop = true

local function constable(name)
	return query1([[
		select c.table_name from information_schema.table_constraints c
		where c.table_schema = ? and c.constraint_name = ?
	]], config'db_name', name)
end

local function dropfk(name)
	if nodrop then return end
	local tbl = constable(name)
	if not tbl then return end
	pq('alter table '..tbl..' drop foreign key '..name..';')
end

local function droptable(name)
	if nodrop then return end
	pq('drop table if exists '..name..';')
end

local function fkname(tbl, col)
	return string.format('fk_%s_%s', tbl, col:gsub('%s', ''):gsub(',', '_'))
end

function qmacro.fk(tbl, col, ftbl, fcol, ondelete, onupdate)
	ondelete = ondelete or 'cascade'
	onupdate = onupdate or 'restrict'
	local a1 = ondelete ~= 'restrict' and ' on delete '..ondelete or ''
	local a2 = onupdate ~= 'restrict' and ' on update '..onupdate or ''
	return string.format(
		'constraint %s foreign key (%s) references %s (%s)%s%s',
		fkname(tbl, col), col, ftbl, fcol or col, a1, a2)
end

function qmacro.uk(tbl, col)
	return string.format(
		'constraint uk_%s_%s unique key (%s)',
		tbl, col:gsub('%s', ''):gsub(',', '_'), col)
end

local function fk(tbl, col, ...)
	if constable(fkname(tbl, col)) then return end
	local sql = string.format('alter table %s add ', tbl)..
		qmacro.fk(tbl, col, ...)..';'
	pq(sql)
end

------------------------------------------------------------------------------

--ddl commands
qsubst'table  create table if not exists'

--type domains
qsubst'id      int unsigned'
qsubst'pk      int unsigned primary key auto_increment'
qsubst'name    varchar(64) character set utf8 collate utf8_general_ci'
qsubst'email   varchar(128) character set utf8 collate utf8_general_ci'
qsubst'hash    varchar(40) character set ascii' --hmac_sha1 in hex
qsubst'url     varchar(2048) character set utf8 collate utf8_general_ci'
qsubst'bool    tinyint not null default 0'
qsubst'bool1   tinyint not null default 1'
qsubst'ctime   timestamp not null'
qsubst'mtime   timestamp not null on update current_timestamp'
qsubst'money   decimal(20,6)'
qsubst'qty     decimal(20,6)'
qsubst'percent decimal(20,6)'
qsubst'lang    char(2) character set ascii not null'

--drop everything
nodrop = true
droptable'convrate'
droptable'nlemail'
droptable'ordrlog'
droptable'ordritem'
droptable'ordr'
droptable'cartitem'
droptable'usr'
droptable'filterprod'
droptable'filterval'
droptable'filtercat'
droptable'filter'
droptable'promocode'

nodrop = false
droptable'combival'
droptable'combi'
droptable'img'
droptable'prodname'
droptable'prod'
droptable'descrval'
droptable'descr'
droptable'valname'
droptable'val'
droptable'dimname'
droptable'dim'

--create everything

pq[[
$table dim (   --color, size, ...
	did         $pk,
	descr       text
);
]]

pq[[
$table dimname (
	did         $id not null, $fk(dimname, did, dim),
	dlang       $lang,
	dname       $name,
	primary key (did, dlang)
);
]]

pq[[
$table val (   --red, green, small, large, ...
	vid         $pk,
	did         $id not null, $fk(val, did, dim),
	descr       text,
	pvid        $id, $fk(val, pvid, val, vid)
);
]]

pq[[
$table valname (
	vid         $id not null, $fk(valname, vid, val),
	vlang       $lang,
	vname       $name,
	primary key (vid, vlang)
);
]]

pq[[
$table prod (
	pid         $pk,
	sku         $name
);
]]

pq[[
$table prodname (
	pid         $id not null, $fk(prodname, pid, prod),
	plang       $lang,
	pname       $name,
	descr       text,
	primary key (pid, plang)
);
]]

pq[[
$table img (
	imgid       $pk
);
]]

pq[[
$table combi ( --(combi1, combi2, ...) -> product1
	coid        $pk,
	pid         $id not null, $fk(combi, pid, prod),
	active      $bool1,
	browsable   $bool1,
	price       $money,
	msrp        $money,
	stock       $qty not null,
	imgid       $id, $fk(combi, imgid, img),
	ctime       $ctime,
	mtime       $mtime
);
]]

pq[[
$table combival ( --(small, red) -> combi1, ...
	coid        $id not null, $fk(combival, coid, combi),
	vid         $id, $fk(combival, vid, val),
	primary key (coid, vid)
);
]]

------------------------------------------------------------------------------

pq[[
$table filter (
	fid         $pk,
	name        $name,
	en_name     $name,
	pos         $id
);
]]

pq[[
$table filtercat (
	fid         $id,
	catid       $id,
	pos         $id,
	primary key (fid, catid)
);
]]

pq[[
$table filterval (
	vid         $pk,
	fid         $id,
	name        $name,
	en_name     $name,
	pos         $id,
	index idx_filterval_en_name (en_name)
);
]]

pq[[
$table filterprod (
	pid         $id,
	vid         $id,
	primary key (pid, vid)
);
]]

------------------------------------------------------------------------------

pq[[
$table usr (
	uid         $pk,
	anonymous   $bool1,
	email       $email,
	emailvalid  $bool,
	pass        $hash,
	facebookid  $name,
	googleid    $name,
	gimgurl     $url,
	active      $bool1,
	name        $name,
	phone       $name,
	gender      $name,
	birthday    date,
	newsletter  $bool,
	admin       $bool,
	note        text,
	clientip    $name,
	promocode   $name,
	codesent    bool,
	atime       timestamp not null default 0,
	ctime       $ctime,
	mtime       $mtime
);
]]

pq[[
$table usrtoken (
	token       $hash not null primary key,
	uid         $id not null,
	ctime       $ctime
);
]]

pq[[
$table cartitem (
	ciid        $pk,
	uid         $id not null, $fk(cartitem, uid, usr),
	pid         $id not null, $fk(cartitem, pid, ps_product, id_product),
	coid        $id, $fk(cartitem, coid, ps_product_attribute, id_product_attribute),
	qty         $id not null default 1,
	pos         $id,
	buylater    $bool,
	ctime       $ctime,
	mtime       $mtime
);
]]

pq[[
$table ordr (
	oid         $pk,
	uid         $id not null, $fk(ordr, uid, usr),
	email       $email,
	name        $name,
	phone       $name,
	addr        text,
	city        $name,
	county      $name,
	country     $name,
	note        text,
	shiptype    $name not null,
	shipcost    $money not null,
	promocode   $name,
	discount    $money not null default 0,
	status      $name,
	opuid       $id, $fk(ordr, opuid, usr, uid),
	opnote      text,
	ctime       $ctime,
	mtime       $mtime
);
]]

pq[[
$table ordritem (
	oiid        $pk,
	oid         $id not null, $fk(ordritem, oid, ordr),
	coid        $id not null, $fk(ordritem, coid, ps_product_attribute, id_product_attribute),
	qty         $id not null default 1,
	price       $money not null,
	note        text,
	status      $name,
	opuid       $id, $fk(ordritem, opuid, usr, uid),
	ctime       $ctime,
	mtime       $mtime
);
]]

pq[[
$table nlemail (
	email       $email primary key,
	clientip    $name,
	mtime       timestamp
);
]]

pq[[
$table convrate (
	ron         $money not null,
	usd         $money not null,
	date        date not null,
	primary key (ron, usd, date)
)
]]

pq[[
$table promocode (
	promocode   $name primary key,
	expires     timestamp not null,
	discount    $percent,
	reason      $name,
	uid         $id
);
]]

--create fulltext indices
--pq'create fulltext index ft_name on ps_product_lang(name)'
--pq'create fulltext index ft_description on ps_product_lang(description)'
--pq'create fulltext index ft_name on ps_manufacturer(name)'
