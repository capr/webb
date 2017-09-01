require'ddl'

droptable'usrtoken'
droptable'usr'

print_queries(true)

query[[
$table usr (
	uid         $pk,
	anonymous   $bool1,
	email       $email,
	emailvalid  $bool,
	pass        $hash,
	facebookid  $name,
	googleid    $name,
	gimgurl     $url,  --google image url
	active      $bool1,
	name        $name,
	phone       $name,
	gender      $name,
	birthday    date,
	newsletter  $bool,
	admin       $bool,
	note        text,
	clientip    $name, --when it was created
	atime       $atime, --last access time
	ctime       $ctime, --creation time
	mtime       $mtime  --last modification time
);
]]

query[[
$table usrtoken (
	token       $hash not null primary key,
	uid         $id not null, $fk(usrtoken, uid, usr),
	ctime       $ctime
);
]]

