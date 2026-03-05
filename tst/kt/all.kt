@Test
fun a0 () {
    // proof that data-class synchronized is "by ref" not "by value"
    // we need "by value" because same chain might be loaded by different threads/sockets
    data class XXX (val a: Int, val b: Int)
    val v1 = XXX(10,20)
    val v2 = XXX(10,20)
    val t1 = thread {
        synchronized(v1) {
            Thread.sleep(10000)
        }
    }
    Thread.sleep(100)
    println("antes")
    synchronized(v2) {
        println("dentro")
    }
    println("depois")
}

@Test
fun a1_json() {
    @Serializable
    data class MeuDado(val v: String)

    val bs: MutableList<Byte> = mutableListOf()
    for (i in 0..255) {
        bs.add(i.toByte())
    }
    val x = bs.toByteArray().toString(Charsets.ISO_8859_1)
    //println(x)
    val s = MeuDado(x)
    //println(s)
    //@OptIn(UnstableDefault::class)
    val json = Json { prettyPrint = true }
    val a = json.encodeToString(MeuDado.serializer(), s)
    val b = json.decodeFromString(MeuDado.serializer(), a)
    val c = b.v.toByteArray(Charsets.ISO_8859_1)
    assert_(bs.toByteArray().contentToString() == c.contentToString())
}
@Test
fun a2_shared() {
    val str = "Alo 1234"
    val enc = str.toByteArray().encryptShared(SHA0)
    val dec = enc.decryptShared(SHA0).toString(Charsets.UTF_8)
    //println(str.length.toString() + " vs " + dec.length)
    assert(str == dec)
}
@Test
fun a3_pubpvt() {
    val str = "Alo 1234"
    val enc = str.toByteArray().encryptPublic(PUB0)
    val dec = enc.decryptPrivate(PVT0).toString(Charsets.UTF_8)
    //println(str.length.toString() + " vs " + dec.length)
    assert(str == dec)
}
@Test
fun a4_minus() {
    val s1 = sortedSetOf(1,2,5,10)
    val s2 = sortedSetOf(3,5,7,10)
    assert(sortedMinus(s1.sortedCopy(),s2.sortedCopy()) == sortedSetOf(1,2))
    assert(sortedMinus(s2.sortedCopy(),s1.sortedCopy()) == sortedSetOf(3,7))

    val s3 = sortedSetOf(4,5,7,8)
    val s4 = sortedSetOf(3,5,7,10)
    assert(sortedMinus(s3.sortedCopy(),s4.sortedCopy()) == sortedSetOf(4,8))
    assert(sortedMinus(s4.sortedCopy(),s3.sortedCopy()) == sortedSetOf(3,10))
}

@Test
fun b1_host() {
    Host_load("/tmp/xxx.${getNow()}/")
    var ok = false
    try {
        Host_load("/")
    } catch (e: Exception){
        ok = true
        assert(e.message!!.contains("(Permission denied)"))
    }
    assert(ok)
}
@Test
fun b2_chain() {
    val h = Host_load("/tmp/freechains/tests/local/")
    val c1 = h.chainsJoin("#uerj", listOf(PUB0))

    val c2 = h.chainsLoad(c1.name)
    println(c2.cons)
    assert_(c1.hashCode().equals(c2.hashCode()))

    val hash = c2.blockNew(null, null, B(""), false, null)
    val blk2 = c2.fsLoadBlock(hash)
    assert_(c2.fsLoadBlock(hash).hashCode().equals(blk2.hashCode()))
}

@Test
fun c1_post() {
    val loc = Host_load("/tmp/freechains/tests/local/")
    val chain = loc.chainsJoin("@$PUB0", emptyList())
    val n1 = chain.blockNew(PVT0, null, B(""), false, null)
    val n2 = chain.blockNew(PVT0, null, B(""), false, null)
    val n3 = chain.blockNew(null, null, B(""), false, null)

    var ok = false
    try {
        val b3 = chain.fsLoadBlock(n3)
        val n = b3.copy(immut=b3.immut.copy(pay=b3.immut.pay.copy(hash="xxx")))
        chain.blockAssert(n, 0)
    } catch (e: Throwable) {
        ok = true
    }
    assert_(ok)

    assert_(chain.fsExistsBlock(chain.genesis()))
    //println(n1.toHeightHash())
    assert_(chain.fsExistsBlock(n1))
    assert_(chain.fsExistsBlock(n2))
    assert_(chain.fsExistsBlock(n3))
    assert_(!chain.fsExistsBlock("2_........"))

    val big = ".".repeat(200*1000)
    val n4 = chain.blockNew(PVT0, null, B(big), false, null)
    assert(n4.startsWith("3_"))
    try {
        chain.blockNew(null, null, B(big), false, null)
    } catch (e: Throwable) {
        assert(e.message == "post is too large")
    }
}
@Test
fun c02_blocked() {
    val loc = Host_load("/tmp/freechains/tests/C02/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    val n1 = chain.blockNew(PVT0, null, B("1"), false, null)
    val n2 = chain.blockNew(PVT1, null, B("2.1"), false, null)
    val n3 = chain.blockNew(PVT1, null, B("2.2"), false, null)
    assert(chain.heads(Head_State.LINKED).let { it.size==1 && it.contains(n1) })
    assert(chain.heads(Head_State.BLOCKED).let { it.size==2 && it.contains(n2) && it.contains(n3) })
    check_reset(chain)
}

@Test
fun c03_all() {
    val loc = Host_load("/tmp/freechains/tests/C03/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val n1 = chain.blockNew(PVT0, null, B("1"), false, null)
    val n2 = chain.blockNew(PVT0, null, B("2"), false, null)
    val n3 = chain.blockNew(PVT0, null, B("3"), false, null)

    val all = chain.allFroms(chain.heads(Head_State.LINKED))
    assert(all.size==4 && all.contains(n3))
    val rep1 = chain.reps.getZ(PUB0)
    assert(rep1 == 30)
    setNow(12*hour+100)
    chain.consensus()
    val rep2 = chain.reps.getZ(PUB0)
    assert(rep2 == 30)
    check_reset(chain)
}
@Test
fun c04_all() {
    val loc = Host_load("/tmp/freechains/tests/C04/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    chain.consensus()
    assert(30 == chain.reps.getZ(PUB0))
    val n1 = chain.blockNew(PVT0, null, B("1"), false, null)
    assert(30 == chain.reps.getZ(PUB0))
    setNow(12*hour+100)
    chain.consensus()
    assert(30 == chain.reps.getZ(PUB0))
    val n2 = chain.blockNew(PVT0, null, B("2"), false, null)
    assert(30 == chain.reps.getZ(PUB0))
    setNow(24*hour+200)
    chain.consensus()
    assert(30 == chain.reps.getZ(PUB0))
    val n3 = chain.blockNew(PVT0, null, B("3"), false, null)
    assert(30 == chain.reps.getZ(PUB0))
    check_reset(chain)
}
@Test
fun c05_seq() {
    val loc = Host_load("/tmp/freechains/tests/C05/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val a1 = chain.blockNew(PVT0, null, B("a1"), false, null)
    val a2 = chain.blockNew(PVT0, null, B("a2"), false, null)
    val b2 = chain.blockNew(PVT1, null, B("b2"), false, setOf(a1))

    // gen <- a1 <- a2      // PVT0
    //          \-- b2      // PVT1

    assert(chain.heads(Head_State.LINKED).let  { it.size==1 && it.contains(a2) })
    assert(chain.heads(Head_State.BLOCKED).let { it.size==1 && it.contains(b2) })
    assert(30 == chain.reps.getZ(PUB0))

    val a3 = chain.blockNew(PVT0, Like(1,b2), B("a3"), false, null)

    // gen -- a1 -- a2
    //          \-- b2 -- a3

    assert(chain.heads(Head_State.LINKED).let  { it.size==2 && it.contains(a3) && it.contains(a2)})
    assert(chain.heads(Head_State.BLOCKED).let { it.size==0 })
    assert(29 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))

    setNow(12*hour+100)
    chain.consensus()
    assert(29 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))

    setNow(24*hour+200)
    chain.consensus()
    assert(30 == chain.reps.getZ(PUB0))
    assert( 2 == chain.reps.getZ(PUB1))

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    if (b2>a2) {
        assert(str == ",a1,a2,b2,a3")
    } else {
        assert(str == ",a1,b2,a2,a3")
    }
    check_reset(chain)
}
@Test
fun c06_ord1() {
    val loc = Host_load("/tmp/freechains/tests/C06/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(1,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    assert(chain.heads(Head_State.LINKED).let  { it.size==1 && it.contains(a4) })
    assert(chain.heads(Head_State.BLOCKED).let { it.size==0 })
    assert(28 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))
    assert( 1 == chain.reps.getZ(PUB2))

    setNow(13*hour)
    chain.consensus()
    assert(28 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))
    assert( 1 == chain.reps.getZ(PUB2))

    val a5 = chain.blockNew(PVT0, null, B("a5"), false, setOf(a4))
    val c5 = chain.blockNew(PVT2, null, B("c5"), false, setOf(a4))
    val b5 = chain.blockNew(PVT1, null, B("b5"), false, setOf(a4))

    val str1 = chain.cons.map { chain.fsLoadPayRaw(it).utf8() }.joinToString(",")
    //println(str1)
    if (b5 > c5) {
        assert(str1 == ",b1,a2,c3,a4,a5,c5,b5")
    } else {
        assert(str1 == ",b1,a2,c3,a4,a5,b5,c5")
    }

    val a6 = chain.blockNew(PVT0, null, B("a6"), false, setOf(a5,b5))
    val a7 = chain.blockNew(PVT0, null, B("a7"), false, setOf(a6,c5))

    //                            /----- c5 -----\
    // gen <- b1 <- a2 <- c3 <- a4 <- a5 <- a6 <- a7
    //                            \-- b5 --/

    assert(chain.heads(Head_State.LINKED).size==1 && chain.heads(Head_State.BLOCKED).size==0)
    assert(chain.heads(Head_State.LINKED).contains(a7))
    assert(28 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))
    assert( 1 == chain.reps.getZ(PUB2))

    val str3 = chain.cons.map { chain.fsLoadPayRaw(it).utf8() }.joinToString(",")
    assert(str3 == ",b1,a2,c3,a4,a5,b5,a6,c5,a7")
    //              ,b1,a2,c3,a4,a5,c5,b5,a6,a7
    //assert(str == ",b1,a2,c3,a4,c5,a5,b5,a6,a7")

    setNow(25*hour)
    chain.consensus()
    assert(28 == chain.reps.getZ(PUB0))
    assert( 2 == chain.reps.getZ(PUB1))
    assert( 2 == chain.reps.getZ(PUB2))

    setNow(38*hour)
    chain.consensus()
    assert(29 == chain.reps.getZ(PUB0))
    assert( 2 == chain.reps.getZ(PUB1))
    assert( 2 == chain.reps.getZ(PUB2))
    check_reset(chain)
}
@Test
fun c07_ord2() {
    val loc = Host_load("/tmp/freechains/tests/C07/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(1,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    setNow(13*hour)
    chain.consensus()
    val a5 = chain.blockNew(PVT0, null, B("a5"), false, setOf(a4))
    val b5 = chain.blockNew(PVT1, null, B("b5"), false, setOf(a4))
    val a6 = chain.blockNew(PVT0, null, B("a6"), false, setOf(a5,b5))
    val c6 = chain.blockNew(PVT2, null, B("c6"), false, setOf(a5))
    val a7 = chain.blockNew(PVT0, null, B("a7"), false, setOf(a6,c6))

    //                                  /-- c6 --\
    // gen <- b1 <- a2 <- c3 <- a4 <- a5 <- a6 <- a7
    //                            \-- b5 --/

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    assert(str == ",b1,a2,c3,a4,a5,b5,a6,c6,a7")
    //assert(str == ",b1,a2,c3,a4,a5,c6,b5,a6,a7")
    check_reset(chain)
}
@Test
fun c08_ord3() {
    val loc = Host_load("/tmp/freechains/tests/C08/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(2,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    setNow(13*hour)
    chain.consensus()
    val a5 = chain.blockNew(PVT0, null, B("a5"), false, setOf(a4))
    val b5 = chain.blockNew(PVT1, null, B("b5"), false, setOf(a4))
    val c5 = chain.blockNew(PVT2, null, B("c5"), false, setOf(a4))
    val c6 = chain.blockNew(PVT2, null, B("c6"), false, setOf(a5,c5))
    val a6 = chain.blockNew(PVT0, null, B("a6"), false, setOf(a5,b5))
    val a7 = chain.blockNew(PVT0, null, B("a7"), false, setOf(a6,c6))

    //                            /-- c5 -/ c6 --\
    // gen <- b1 <- a2 <- c3 <- a4 <- a5 <- a6 <- a7
    //                            \-- b5 --/

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    assert(str == ",b1,a2,c3,a4,a5,b5,a6,c5,c6,a7")
    //assert(str == ",b1,a2,c3,a4,a5,c5,c6,b5,a6,a7")
    check_reset(chain)
}
@Test
fun c09_ord4() {
    val loc = Host_load("/tmp/freechains/tests/C09/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(2,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    setNow(13*hour)
    chain.consensus()
    val a5 = chain.blockNew(PVT0, null, B("a5"), false, setOf(a4))
    val b5 = chain.blockNew(PVT1, null, B("b5"), false, setOf(a4))
    val c5 = chain.blockNew(PVT2, null, B("c5"), false, setOf(a4))
    val a6 = chain.blockNew(PVT0, null, B("a6"), false, setOf(a5,b5,c5))

    //                            /-- c5 --\
    // gen <- b1 <- a2 <- c3 <- a4 <- a5 <- a6
    //                            \-- b5 --/

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    assert(str == ",b1,a2,c3,a4,a5,c5,b5,a6")
    check_reset(chain)
}
@Test
fun c10_inv1() {
    val loc = Host_load("/tmp/freechains/tests/C10/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(2,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    assert(str == ",b1,a2,c3,a4")
    //assert(con.invs.isEmpty())
    check_reset(chain)
}
@Test
fun c11_inv2() {
    val loc = Host_load("/tmp/freechains/tests/C11/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))

    setNow(0)
    val b1 = chain.blockNew(PVT1, null, B("b1"), false, null)
    val a2 = chain.blockNew(PVT0, Like(1,b1), B("a2"), false, null)
    val c3 = chain.blockNew(PVT2, null, B("c3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(2,c3), B("a4"), false, null)

    // gen <- b1 <- a2 <- c3 <- a4

    setNow(13*hour)

    chain.consensus()
    assert(2 == chain.reps.getZ(PUB2))
    assert(1 == chain.reps.getZ(PUB1))

    setNow(25*hour)

    chain.consensus()
    assert(3 == chain.reps.getZ(PUB2))
    assert(2 == chain.reps.getZ(PUB1))

    val c5 = chain.blockNew(PVT2, null, B("c5"), false, setOf(a4))
    val c6 = chain.blockNew(PVT2, null, B("c6"), false, setOf(c5))

    assert(1 == chain.reps.getZ(PUB2))

    val c7 = chain.blockNew(PVT2, null, B("c7"), false, setOf(c6))
    val b5 = chain.blockNew(PVT1, null, B("b5"), false, setOf(a4))
    val a6 = chain.blockNew(PVT0, Like(-2,c3), B("a6"), false, setOf(b5))

    //                            /-- c5 -- c6 -- c7
    // gen <- b1 <- a2 <- c3 <- a4
    //                            \-- b5 -- a6

    val str = chain.cons.map { chain.fsLoadPayRaw(it).toString(Charsets.UTF_8) }.joinToString(",")
    //println(str)
    assert(str == ",b1,a2,c3,a4,b5,a6,c5")
    //assert(str == ",b1,a2,c3,a4,b5,a6,c5")
    //assert(str == ",b1,a2,c3,a4,c5,c6,b5,a6,c7")
    //println(inv)
    //assert(con4.invs.let { it.size==2 && it.contains(c6) && it.contains(c7) })
    check_reset(chain)
}
@Test
fun c12_dt12h() {
    val loc = Host_load("/tmp/freechains/tests/C12/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0))
    setNow(0)
    val a1 = chain.blockNew(PVT0, null, B("a1"), false, null)
    val a2 = chain.blockNew(PVT0, null, B("a2"), false, null)

    // gen <- a1 <- a2

    assert(30 == chain.reps.getZ(PUB0))

    val b3 = chain.blockNew(PVT1, null, B("b3"), false, null)
    val a4 = chain.blockNew(PVT0, Like(1, b3), B("a4"), false, null)

    // gen <- a1 <- a2 <- b3 <- a4

    assert(29 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))

    val c5 = chain.blockNew(PVT2, null, B("c5"), false, null)
    val b6 = chain.blockNew(PVT1, Like(1, c5), B("b6"), false, null)

    // gen -- a1 -- a2 -- b3 -- a4 -- c5 -- b6

    assert(29 == chain.reps.getZ(PUB0))
    assert( 0 == chain.reps.getZ(PUB1))
    assert( 0 == chain.reps.getZ(PUB2))

    setNow(11*hour + 59*min)
    chain.consensus()
    assert(29 == chain.reps.getZ(PUB0))
    assert( 0 == chain.reps.getZ(PUB1))
    assert( 0 == chain.reps.getZ(PUB2))

    setNow(12*hour + 100)
    chain.consensus()
    assert(29 == chain.reps.getZ(PUB0))
    assert( 0 == chain.reps.getZ(PUB1))
    assert( 1 == chain.reps.getZ(PUB2))

    setNow(24*hour + 100)
    chain.consensus()
    assert(30 == chain.reps.getZ(PUB0))
    assert( 1 == chain.reps.getZ(PUB1))
    assert( 2 == chain.reps.getZ(PUB2))
    check_reset(chain)
}
@Test
fun c13_pioneers() {
    val loc = Host_load("/tmp/freechains/tests/C13/")
    val chain = loc.chainsJoin("#xxx", listOf(PUB0,PUB1))
    chain.consensus()
    assert(15 == chain.reps.getZ(PUB0))
    assert(15 == chain.reps.getZ(PUB1))
    check_reset(chain)
}
@Disabled
@Test
fun c14_100s() {
    val loc = Host_load("/tmp/freechains/tests/C03/")
    val chain = loc.chainsJoin("@$PUB0", emptyList())

    for (i in 1..500) {
        val x = chain.blockNew(PVT1, null, B(i.toString()), false, null)
        chain.blockNew(PVT0, Like(1,x), B(i.toString()), false, null)
        //println(i)
        //println(PUB0)
        //println(PUB1)
        check_reset(chain)
    }
    //println(chain.cons)
}
@Disabled
@Test
fun c15 () {
    val pub = "@57B7F4EF65AF1630C64B7A7094E4A01B01C9821622E32ECBB8D7F3B718A367FD"
    val loc = Host_load("/tmp/fc-8510/")
    val chain = loc.chainsLoad(pub)
    check_reset(chain)
    val h1 = chain.heads1(Head_State.LINKED).sorted()
    val h2 = chain.heads2(Head_State.LINKED).sorted()
    assert(h1 == h2) {
        h1 + h2
    }
}
@Disabled
@Test
fun c16 () {
    val pub = "@57B7F4EF65AF1630C64B7A7094E4A01B01C9821622E32ECBB8D7F3B718A367FD"
    val loc = Host_load("/tmp/fc-8501/")
    val chain = loc.chainsLoad(pub)
    //println(chain.cons.joinToString("\n"))
}

@Test
fun d1_proto() {
    // SOURCE
    val src = Host_load("/tmp/freechains/tests/src/")
    val srcChain = src.chainsJoin("@$PUB1", emptyList())
    srcChain.blockNew(PVT1, null, B(""), true, null)
    srcChain.blockNew(PVT1, null, B(""), true, null)
    thread { Daemon(src).daemon() }

    // DESTINY
    val dst = Host_load("/tmp/freechains/tests/dst/", PORT1)
    dst.chainsJoin("@$PUB1", emptyList())
    thread { Daemon(dst).daemon() }
    Thread.sleep(200)

    main_cli_assert(arrayOf("peer", "localhost:$PORT1", "ping")).let {
        //println(">>> $it")
        assert_(it.toInt() < 50)
    }
    main_cli(arrayOf("peer", "localhost:11111", "ping")).let {
        assert_(!it.first && it.second == "! connection refused")
    }
    main_cli_assert(arrayOf("peer", "localhost:$PORT1", "chains")).let {
        assert_(it == "@$PUB1")
    }

    main_cli(arrayOf("peer", "localhost:$PORT1", "send", "@$PUB1"))
    Thread.sleep(200)

    main_cli(arrayOf(H1, "local", "stop"))
    main_cli(arrayOf("local", "stop"))
    Thread.sleep(200)

    // TODO: check if dst == src
    // $ diff -r /tmp/freechains/tests/dst/ /tmp/freechains/tests/src/
}
@Test
fun f1_peers() {
    val h1 = Host_load("/tmp/freechains/tests/h1/", PORT0)
    val h1Chain = h1.chainsJoin("@$PUB1", emptyList())
    h1Chain.blockNew(PVT1, null, B(""), false, null)
    h1Chain.blockNew(PVT1, null, B(""), false, null)

    val h2 = Host_load("/tmp/freechains/tests/h2/", PORT1)
    val h2Chain = h2.chainsJoin("@$PUB1", emptyList())
    h2Chain.blockNew(PVT1, null, B(""), false, null)
    h2Chain.blockNew(PVT1, null, B(""), false, null)

    Thread.sleep(200)
    thread { Daemon(h1).daemon() }
    thread { Daemon(h2).daemon() }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "peer", "localhost:$PORT1", "recv", "@$PUB1"))
    Thread.sleep(200)
    main_cli(arrayOf(H1, "local", "stop"))
    main_cli(arrayOf("local", "stop"))
    Thread.sleep(200)

    // TODO: check if 8332 (h2) < 8331 (h1)
    // $ diff -r /tmp/freechains/tests/h1 /tmp/freechains/tests/h2/
}

@Test
fun g01_128() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/G01/")) }
    Thread.sleep(200)

    main_cli(arrayOf("chains", "join", "#chat", PUB0))
    main_cli_assert(arrayOf("chain", "#chat", "post", "inline", ".".repeat(S128_pay), S0))
    main_cli(arrayOf("chain", "#chat", "post", "inline", ".".repeat(S128_pay+1), S0))
        .let { assert_(!it.first && it.second.equals("! post is too large")) }

    main_cli_assert(arrayOf("chains", "join", "@$PUB0"))
    main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", ".".repeat(S128_pay+1), S0))
    main_cli(arrayOf("chain", "@$PUB0", "post", "inline", ".".repeat(S128_pay+1), S1))
        .let { assert_(!it.first && it.second.equals("! post is too large")) }

    main_cli_assert(arrayOf(H0, "chains", "join", "\$xxx", "password".toShared()))
    main_cli_assert(arrayOf("chain", "\$xxx", "post", "inline", ".".repeat(S128_pay+1), S0))
    main_cli_assert(arrayOf("chain", "\$xxx", "post", "inline", ".".repeat(S128_pay+1), S1))
}

@Test
fun m00_chains() {
    var err = Pair(true,"")
    thread {
        err = main_host(arrayOf("start", "/"))
    }
    Thread.sleep(200)
    assert(!err.first && err.second.contains("/timestamp.txt (Permission denied)"))

    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/M0/"))
    }
    Thread.sleep(200)
    main_host(arrayOf("path")).let {
        assert_(it.first && it.second == "//tmp/freechains/tests/M0//")
    }
    main_cli_assert(arrayOf("chains", "list")).let {
        assert_(it == "")
    }
    main_cli_assert(arrayOf("chains", "leave", "#xxx")).let {
        assert_(it == "false")
    }
    main_cli_assert(arrayOf("chains", "join", "#xxx", PUB0)).let {
        assert_(it.isNotEmpty())
    }
    main_cli_assert(arrayOf("chains", "join", "#yyy", PUB1)).let {
        assert_(it.isNotEmpty())
    }
    main_cli_assert(arrayOf("chains", "list")).let {
        assert_(it=="#yyy #xxx" || it=="#xxx #yyy")
    }
    main_cli_assert(arrayOf("chains", "leave", "#xxx")).let {
        assert_(it == "true")
    }
}
@Test
fun m01_args() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/M1/"))
    }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#xxx", PUB0))

    main_cli(arrayOf("xxx", "yyy")).let {
        assert_(!it.first)
    }
    main_cli(arrayOf()).let {
        assert_(!it.first && it.second.contains("Usage:"))
    }
    main_cli(arrayOf("--help")).let {
        assert_(it.first && it.second.contains("Usage:"))
    }

    assert_(main_cli_assert(arrayOf("chain", "#xxx", "genesis")).startsWith("0_"))
    assert_(main_cli_assert(arrayOf("chain", "#xxx", "heads")).startsWith("0_"))

    main_cli(arrayOf("chain", "#xxx", "post", "inline", "aaa", S0))
    assert_(main_cli_assert(arrayOf("chain", "#xxx", "heads")).startsWith("1_"))
    main_cli_assert(arrayOf("chain", "#xxx", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_cli_assert(arrayOf("chain", "#xxx", "heads")).let { list ->
        list.split(' ').toTypedArray().let {
            assert_(it.size == 1)
            assert_(it[0].startsWith("1_"))
        }
    }

    main_cli(arrayOf("chain", "#xxx", "get", "block", "0_B5E21297B8EBEE0CFA0FA5AD30F21B8AE9AE9BBF25F2729989FE5A092B86B129")).let {
        //println(it)
        assert_(!it.first && it.second.equals("! block not found"))
    }

    /*val h2 =*/ main_cli(arrayOf(S0, "chain", "#xxx", "post", "file", "/tmp/freechains/tests/M1/chains/#xxx/chain"))

    //org.freechains.core.cli(arrayOf(S0, "chain", "/xxx", "post", "file", "/tmp/20200504192434-0.eml"))

    // h0 -> h1 -> h2

    assert_(main_cli_assert(arrayOf("chain", "#xxx", "heads")).startsWith("2_"))
    assert_(main_cli_assert(arrayOf("chain", "#xxx", "heads", "blocked")).isEmpty())

    //org.freechains.core.cli(arrayOf("chain", "#xxx", "post", "file", "base64", "/bin/cat"))
    main_host_assert(arrayOf("stop"))
    // TODO: check genesis 2x, "aaa", "host"
    // $ cat /tmp/freechains/tests/M1/chains/xxx/blocks/*
}
@Test
fun m01_blocked() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/M1B/"))
    }
    Thread.sleep(200)
    main_cli_assert(arrayOf("chains", "join", "#xxx", PUB0))
    main_cli_assert(arrayOf("chain", "#xxx", "post", "inline", "1.1", "--sign=$PVT1"))
    main_cli_assert(arrayOf("chain", "#xxx", "post", "inline", "1.2", "--sign=$PVT1"))
    val x = main_cli_assert(arrayOf("chain", "#xxx", "heads"))
    assert_(!x.contains(" "))
}
@Test
fun m01_trav() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/trav/"))
    }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#", PUB0))
    main_cli_assert(arrayOf("chain", "#", "genesis"))
    main_cli(arrayOf("chain", "#", "post", "inline", "aaa", S0))
    main_cli(arrayOf("chain", "#", "post", "inline", "bbb", S0))
    main_cli_assert(arrayOf("chain", "#", "consensus")).let {
        it.split(" ").let {
            assert_(it.size==3 && it[1].startsWith("1_")) {
                it
            }
        }
    }
}
@Test
fun m01_listen() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/listen/"))
    }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#", PUB0))

    var ok = 0
    val t1 = thread {
        val socket = Socket("localhost", PORT0)
        val writer = DataOutputStream(socket.getOutputStream()!!)
        val reader = DataInputStream(socket.getInputStream()!!)
        writer.writeLineX("$PRE chain # listen")
        val n = reader.readLineX().toInt()
        assert_(n == 1) { "error 1" }
        ok++
    }

    val t2 = thread {
        val socket = Socket("localhost", PORT0)
        val writer = DataOutputStream(socket.getOutputStream()!!)
        val reader = DataInputStream(socket.getInputStream()!!)
        writer.writeLineX("$PRE chains listen")
        val x = reader.readLineX()
        assert_(x == "1 #") { "error 2" }
        ok++
    }

    Thread.sleep(200)
    main_cli(arrayOf("chain", "#", "post", "inline", "aaa", S0))
    t1.join()
    t2.join()
    assert_(ok == 2) { ok }
}
@Test
fun m02_crypto() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/M2/"))
    }
    Thread.sleep(200)
    val lazySodium = LazySodiumJava(SodiumJava())
    val kp: KeyPair = lazySodium.cryptoSignKeypair()
    val pk: Key = kp.publicKey
    val sk: Key = kp.secretKey
    assert_(lazySodium.cryptoSignKeypair(pk.asBytes, sk.asBytes))
    //println("TSTTST: ${pk.asHexString} // ${sk.asHexString}")
    main_cli(arrayOf("keys", "shared", "senha secreta"))
    main_cli(arrayOf("keys", "pubpvt", "senha secreta"))

    val msg = "mensagem secreta"
    val nonce = lazySodium.nonce(SecretBox.NONCEBYTES)
    val key = Key.fromHexString("B07CFFF4BE58567FD558A90CD3875A79E0876F78BB7A94B78210116A526D47A5")
    val encrypted = lazySodium.cryptoSecretBoxEasy(msg, nonce, key)
    //println("nonce=${lazySodium.toHexStr(nonce)} // msg=$encrypted")
    val decrypted = lazySodium.cryptoSecretBoxOpenEasy(encrypted, nonce, key)
    assert_(msg == decrypted)
}
@Test
fun m02_crypto_passphrase() {
    thread {
        main_host_assert(arrayOf("start", "/tmp/freechains/tests/M2/"))
    }
    Thread.sleep(200)

    val s0 = main_cli_assert(arrayOf("keys", "shared", "senha"))
    val s1 = main_cli_assert(arrayOf("keys", "shared", "senha secreta"))
    val s2 = main_cli_assert(arrayOf("keys", "shared", "senha super secreta"))
    assert_(s0 != s1 && s1 != s2)

    val k0 = main_cli_assert(arrayOf("keys", "pubpvt", "senha"))
    val k1 = main_cli_assert(arrayOf("keys", "pubpvt", "senha secreta"))
    val k2 = main_cli_assert(arrayOf("keys", "pubpvt", "senha super secreta"))
    assert_(k0 != k1 && k1 != k2)
}
@Test
fun m02_crypto_pubpvt() {
    val ls = LazySodiumJava(SodiumJava())
    val bobKp = ls.cryptoBoxKeypair()
    val message = "A super secret message".toByteArray()
    val cipherText =
        ByteArray(message.size + Box.SEALBYTES)
    ls.cryptoBoxSeal(cipherText, message, message.size.toLong(), bobKp.publicKey.asBytes)
    val decrypted = ByteArray(message.size)
    val res = ls.cryptoBoxSealOpen(
        decrypted,
        cipherText,
        cipherText.size.toLong(),
        bobKp.publicKey.asBytes,
        bobKp.secretKey.asBytes
    )

    if (!res) {
        println("Error trying to decrypt. Maybe the message was intended for another recipient?")
    }

    println(String(decrypted)) // Should print out "A super secret message"


    val lazySodium = LazySodiumJava(SodiumJava())
    //val kp = ls.cryptoBoxKeypair()

    val pubed = Key.fromHexString("4EC5AF592D177459D2338D07FFF9A9B64822EF5BE9E9715E8C63965DD2AF6ECB").asBytes
    val pvted =
        Key.fromHexString("70CFFBAAD1E1B640A77E7784D25C3E535F1E5237264D1B5C38CB2C53A495B3FE4EC5AF592D177459D2338D07FFF9A9B64822EF5BE9E9715E8C63965DD2AF6ECB")
            .asBytes
    val pubcu = ByteArray(Box.CURVE25519XSALSA20POLY1305_PUBLICKEYBYTES)
    val pvtcu = ByteArray(Box.CURVE25519XSALSA20POLY1305_SECRETKEYBYTES)

    assert_(lazySodium.convertPublicKeyEd25519ToCurve25519(pubcu, pubed))
    assert_(lazySodium.convertSecretKeyEd25519ToCurve25519(pvtcu, pvted))

    val dec1 = "mensagem secreta".toByteArray()
    val enc1 = ByteArray(Box.SEALBYTES + dec1.size)
    lazySodium.cryptoBoxSeal(enc1, dec1, dec1.size.toLong(), pubcu)
    //println(LazySodium.toHex(enc1))

    val enc2 = LazySodium.toBin(LazySodium.toHex(enc1))
    //println(LazySodium.toHex(enc2))
    assert_(Arrays.equals(enc1, enc2))
    val dec2 = ByteArray(enc2.size - Box.SEALBYTES)
    lazySodium.cryptoBoxSealOpen(dec2, enc2, enc2.size.toLong(), pubcu, pvtcu)
    assert_(dec2.toString(Charsets.UTF_8) == "mensagem secreta")
}
@Test
fun m03_crypto_post() {
    val loc = Host_load("/tmp/freechains/tests/M2/")
    val c1 = loc.chainsJoin("\$sym", listOf("password".toShared()))
    c1.blockNew(null, null, B(""), true, null)
    val c2 = loc.chainsJoin("@$PUB0", emptyList())
    c2.blockNew(PVT0, null, B(""), true, null)
}
@Test
fun m04_crypto_encrypt() {
    val loc = Host_load("/tmp/freechains/tests/M2/")
    val c1 = loc.chainsLoad("\$sym")
    val n1 = c1.blockNew(null, null, B("aaa"), true, null)
    val n2 = c1.fsLoadPayCrypt(n1, null)
    assert_(n2.toString(Charsets.UTF_8) == "aaa")
    val n3 = c1.fsLoadPayRaw(n1)
    assert_(n3.toString(Charsets.UTF_8) != "aaa")
}
@Test
fun m05_crypto_encrypt_sym() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M50/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M51/", P1)) }
    Thread.sleep(200)
    main_cli(
            arrayOf(
                    "chains",
                    "join",
                    "#xxx"
            )
    )
    main_cli(
            arrayOf(
                    H1,
                    "chains",
                    "join",
                    "#xxx"
            )
    )

    main_cli(arrayOf("chain", "#xxx", "post", "inline", "aaa", "--encrypt"))
    main_cli(arrayOf("peer", "localhost:$PORT1", "send", "#xxx"))
}
@Test
fun m06_crypto_encrypt_asy() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M60/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M61/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "@$PUB0"))
    main_cli(arrayOf(H1, "chains", "join", "@$PUB0"))
    val hash = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "aaa", S0, "--encrypt"))

    val pay = main_cli_assert(arrayOf("chain", "@$PUB0", "get", "payload", hash, "--decrypt=$PVT0"))
    assert_(pay == "aaa")
    main_cli_assert(arrayOf("chain", "@$PUB0", "get", "payload", hash, "file", "/tmp/xxx.pay", "--decrypt=$PVT0"))
    assert_(File("/tmp/xxx.pay").readText() == "aaa")

    main_cli(arrayOf("peer", "localhost:$PORT1", "send", "@$PUB0"))
    val json2 = main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "get", "block", hash))
    val blk2 = json2.jsonToBlock_()
    assert_(blk2.pay.crypt)

    val h2 = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "bbbb", S1))
    val pay2 = main_cli_assert(arrayOf("chain", "@$PUB0", "get", "payload", h2))
    assert_(pay2 == "bbbb")
}
@Test
fun m06x_crypto_encrypt_asy() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M60x/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M61x/", P1)) }
    Thread.sleep(200)
    main_cli_assert(arrayOf("chains", "join", "@!$PUB0"))
    main_cli_assert(arrayOf(H1, "chains", "join", "@!$PUB0"))
    val hash = main_cli_assert(arrayOf("chain", "@!$PUB0", "post", "inline", "aaa", S0, "--encrypt"))

    val pay = main_cli_assert(arrayOf("chain", "@!$PUB0", "get", "payload", hash, "--decrypt=$PVT0"))
    assert_(pay == "aaa")

    main_cli(arrayOf("peer", "localhost:$PORT1", "send", "@!$PUB0"))
    val json2 = main_cli_assert(arrayOf(H1, "chain", "@!$PUB0", "get", "block", hash))
    val blk2 = json2.jsonToBlock_()
    assert_(blk2.pay.crypt)

    main_cli(arrayOf("chain", "@!$PUB0", "post", "inline", "bbbb", S1)).let {
        assert_(!it.first && it.second.equals("! must be from owner"))
    }
}
@Test
fun m06y_shared() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M60y/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M61y/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M62y/", P2)) }
    Thread.sleep(200)

    main_cli(arrayOf("chains", "join", "\$xxx")).let {
        assert_(!it.first && it.second.equals("! expected shared key"))
    }

    val key1 = "password".toShared()
    val key2 = "xxxxxxxx".toShared()

    main_cli_assert(arrayOf(H0, "chains", "join", "\$xxx", key1))
    main_cli_assert(arrayOf(H1, "chains", "join", "\$xxx", key1))
    main_cli_assert(arrayOf(H2, "chains", "join", "\$xxx", key2))

    val hash = main_cli_assert(arrayOf("chain", "\$xxx", "post", "inline", "aaa"))

    File("/tmp/freechains/tests/M60y/chains/\$xxx/blocks/$hash.pay").readText().let {
        assert_(!it.equals("aaa"))
    }
    main_cli_assert(arrayOf("chain", "\$xxx", "get", "payload", hash)).let {
        assert_(it == "aaa")
    }

    main_cli_assert(arrayOf("peer", "localhost:$PORT1", "send", "\$xxx")).let {
        main_cli_assert(arrayOf(H1, "chain", "\$xxx", "get", "payload", hash)).let {
            assert_(it == "aaa")
        }
    }
    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "\$xxx")).let {
        assert_(it.equals("0 / 2"))
    }
}
@Test
fun m07_genesis_fork() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M70/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M71/", P1)) }
    Thread.sleep(200)

    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))
    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "first-0", S0))
    main_cli(arrayOf(H1, "chains", "join", "#", PUB1))
    main_cli(arrayOf(H1, "chain", "#", "post", "inline", "first-1", S1))
    Thread.sleep(200)

    // H0: g <- f0
    // H1: g <- f1

    val r0 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "recv", "#"))
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "#"))
    assert_(r0 == r1 && r0 == "0 / 2")

    val r00 = main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB0))
    val r11 = main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1))
    val r10 = main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1))
    val r01 = main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB0))
    assert_(r00.toInt() == 30)
    assert_(r11.toInt() == 30)
    assert_(r10.toInt() == 0)
    assert_(r01.toInt() == 0)

    main_host_assert(arrayOf(P0, "now", (getNow() + 1 * day).toString()))
    main_host_assert(arrayOf(P1, "now", (getNow() + 1 * day).toString()))

    val x0 = main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB0))
    val x1 = main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1))
    assert_(x0.toInt() == 30)
    assert_(x1.toInt() == 30)
}
@Test
fun m08_likes() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M90/")) }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#chat", PUB0))
    main_cli_assert(arrayOf("chain", "#chat", "post", "inline", "h1", S0))
    val h2 = main_cli_assert(arrayOf("chain", "#chat", "post", "inline", "h2", S1))
    main_cli_assert(arrayOf("chain", "#chat", "like", h2, S0))
    main_cli_assert(arrayOf("chain", "#chat", "like", h2, S0))

    // g -- h1 -- h2 -- l1 -- l2

    assert_("2" == main_cli_assert(arrayOf("chain", "#chat", "reps", PUB1)))
    val h5 = main_cli_assert(arrayOf("chain", "#chat", "post", "inline", "h5", S1))
    main_cli_assert(arrayOf("chain", "#chat", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
        }
        assert_(str == h5)
    }
}
@Test
fun m09_likes() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M90/")) }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "@$PUB0"))

    main_host_assert(arrayOf(P0, "now", "0"))

    val a1 = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "a1", S0))
    val b2 = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "b2", S1))
    val a2 = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "a2", S0))

    // h0 -- a1 -- a2
    //         \-- b2

    main_cli_assert(arrayOf("chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
        }
        assert_(str.startsWith("2_"))
    }

    val l3 = main_cli_assert(arrayOf("chain", "@$PUB0", "like", b2, S0, "--why=l3")) // l3

    // h0 -- a1 -- a2
    //         \-- b2 -- l3

    main_cli_assert(arrayOf("chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 2)
            assert_(it.contains(l3) && it.contains(a2))
        }
    }
    assert_("1" == main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)))

    main_host_assert(arrayOf(P0, "now", (3 * hour).toString()))
    val a4 = main_cli_assert(arrayOf("chain", "@$PUB0", "post", "inline", "a4", S0))

    // h0 -- a1 -- a2 -------- a4
    //         \-- b2 -- l3 --/

    main_host_assert(arrayOf(P0, "now", (1 * day + 4 * hour).toString()))

    assert_(main_cli_assert(arrayOf("chain", "@$PUB0", "heads")).startsWith("4_"))
    assert_("30" == main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)))
    assert_("2" == main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)))

    // like myself
    main_cli_assert(arrayOf("chain", "@$PUB0", "like", a1, S0)).let {
        assert_(it == "like must not target itself")
    }

    val l5 = main_cli_assert(arrayOf("chain", "@$PUB0", "like", b2, S0, "--why=l5"))
    assert_("3" == main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)))

    // h0 -- a1 -- a2 -------- a4 -- l5
    //         \-- b2 -- l3 --/

    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "29")
    }
    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)).let {
        assert_(it == "3")
    }

    main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
        }
        assert_(str.contains("5_"))
    }

    // height is ~also 5~ 6
    val l6 = main_cli_assert(arrayOf("chain", "@$PUB0", "dislike", l5, "--why=l6", S1))

    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6
    //         \-- b2 -- l3 --/

    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)).let {
        assert_(it == "2")
    }
    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "28")
    }

    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M81/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf(H1, "chains", "join", "@$PUB0"))

    main_host_assert(arrayOf(P1, "now", (1 * day + 4 * hour).toString()))

    val n1 = main_cli_assert(arrayOf(H0, "peer", "localhost:$PORT1", "send", "@$PUB0"))
    assert_(n1 == "7 / 7")

    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6
    //         \-- b2 -- l3 --/

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads")).let {
        assert_(it.startsWith("6_"))
    }
    val r1 = main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1))
    assert_("2" == r1) { r1 }
    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "28")
    }

    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB1)).let {
        assert_(it == "2") { it }
    }
    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "28") { it }
    }

    val x7 = main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "post", "inline", "no rep", S1))
    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "reps", PUB1)).let {
        assert_(it == "1") { it }
    }
    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6
    //         \-- b2 -- l3 --/              \-- x7

    main_cli_assert(arrayOf(H0, "peer", "localhost:$PORT1", "recv", "@$PUB0")).let {
        assert_(it == "1 / 1")
    }
    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads")).let {
        assert_(it.startsWith("7_"))
    }
    main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", PUB1)).let {
        assert_(it == "1") { it }
    }
    main_cli_assert(arrayOf("chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "28") { it }
    }

    main_cli(arrayOf(H1, "chain", "@$PUB0", "like", x7, S0))

    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6      /-- l8
    //         \-- b2 -- l3 --/              \-- x7

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
            it.forEach {
                assert_(it.startsWith("8_"))
            }
        }
    }

    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "@$PUB0")).let {
        assert_(it == "1 / 1")
    }

    // flush after 2h
    main_host_assert(arrayOf(P0, "now", "${1 * day + 7 * hour}"))
    main_host_assert(arrayOf(P1, "now", "${1 * day + 7 * hour}"))

    main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
            it.forEach {
                assert_(it.startsWith("8_"))
            }
        }
    }
    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
            it.forEach {
                assert_(it.startsWith("8_"))
            }
        }
    }

    // new post, no rep
    val x9 = main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "post", "inline", "no sig"))

    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6      /-- l8
    //         \-- b2 -- l3 --/              \-- x7      \-- x9

    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "@$PUB0")).let {
        assert_(it.equals("1 / 1"))
    }

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads", "blocked")).let {
        assert_(it.startsWith("9_"))
    }

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "get", "payload", x9))
        .let {
            assert_(it == "no sig")
        }

    // like post w/o pub
    main_cli(arrayOf(H1, "chain", "@$PUB0", "like", x9, S0))

    // h0 -- a1 -- a2 -------- a4 -- l5 -- l6      /-- l8      /-- l10
    //         \-- b2 -- l3 --/              \-- x7      \-- x9

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "heads")).let {
        assert_(it.startsWith("10_"))
    }
    main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "heads", "blocked")).let {
        assert_(it.startsWith("9_"))
    }
    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "@$PUB0")).let {
        //println(it)
        assert_(it == "1 / 1")
    }
    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "26") { it }
    }

    main_host_assert(arrayOf(P1, "now", "${1 * day + 10 * hour}"))

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "26")
    }
    main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", PUB0)).let {
        assert_(it == "26")
    }

    val ln = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", x7))
    val x1 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", a1))
    val x2 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", b2))
    val x3 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", l5))
    val x4 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "reps", x9))
    //println("$ln // $x1 // $x2 // $x3 // $x4")
    assert_(ln == "1" && x1 == "0" && x2 == "2" && x3 == "-1" && x4 == "1")
}
@Test
fun m10_cons() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M100/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M101/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "@$PUB0"))
    main_cli(arrayOf(H1, "chains", "join", "@$PUB0"))
    main_host_assert(arrayOf(P0, "now", "0"))
    main_host_assert(arrayOf(P1, "now", "0"))

    val h1 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "post", "inline", "h1", S0))
    val h2 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "post", "inline", "h2", S0))
    val hx = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "post", "inline", "hx", S1))

    // h1 <- h2 (a) <- hx (r)

    val ps1 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "heads"))
    val rs1 = main_cli_assert(arrayOf(H0, "chain", "@$PUB0", "heads", "blocked"))
    assert_(!ps1.contains(h1) && ps1.contains(h2) && !ps1.contains(hx))
    assert_(!rs1.contains(h1) && !rs1.contains(h2) && rs1.contains(hx))

    main_cli(arrayOf(H1, "peer", "localhost:$PORT0", "recv", "@$PUB0"))

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "post", "inline", "h3", S0)).let {
        //assert_(it == "backs must be accepted")
    }

    // h1 <- h2 (a) <- hx (r)
    //             \<- h3

    main_host_assert(arrayOf(P1, "now", "${3 * hour}"))

    val h4 = main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "post", "inline", "h4", S0))
    assert_(h4.startsWith("4_"))

    // h1 <- h2 (a) <- h3 <- h4
    //              \-- hx (r)

    main_cli(arrayOf(H0, "peer", "localhost:$PORT1", "send", "@$PUB0"))
    main_host_assert(arrayOf(P1, "now", "${6 * hour}"))

    main_cli_assert(arrayOf(H1, "chain", "@$PUB0", "post", "inline", "h5")).let {
        assert_(it.startsWith("5_"))
    }
}
@Test
fun m11_send_after_tine() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M100/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M101/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))
    main_cli(arrayOf(H1, "chains", "join", "#", PUB0))

    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "h1", S0))
    val h2 = main_cli_assert(arrayOf(H0, "chain", "#", "post", "inline", "h2"))
    main_cli(arrayOf(H0, "chain", "#", "like", h2, S0))
    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "h3"))

    main_cli(arrayOf(H0, "peer", "localhost:$PORT1", "send", "#"))

    // this all to test an internal assertion
}
@Test
fun m12_state () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M120/")) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))
    main_host_assert(arrayOf(P0, "now", "0"))

    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M121/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf(H1, "chains", "join", "#", PUB0))
    main_host_assert(arrayOf(P1, "now", "0"))

    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "h1", S0))
    val h21 = main_cli_assert(arrayOf(H0, "chain", "#", "post", "inline", "h21"))
    val h22 = main_cli_assert(arrayOf(H0, "chain", "#", "post", "inline", "h22"))

    // h0 -- h1 -- h21
    //          -- h22

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let {
        assert_(it.startsWith("1_")) { it }
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.startsWith("2_")) { it }
    }

    main_cli(arrayOf(H0, "chain", "#", "like", h21, S0))

    // h0 -- h1 -- h21 -- l2
    //          -- h22

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
            it.forEach {
                assert_(it.startsWith("3_"))
            }
        }
    }

    main_cli(arrayOf(H0, "chain", "#", "like", h22, S0))

    // h0 -- h1 -- h21 -- l2
    //          -- h22 -- l3

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let {
        it.split(' ').let {
            assert_(it.size == 2)
        }
    }
    assert_(main_cli_assert(arrayOf("chain", "#", "heads", "blocked")).isEmpty())

    main_cli_assert(arrayOf(H0, "peer", "localhost:$PORT1", "send", "#")).let {
        assert_(it.contains("5 / 5"))
    }

////////
    // all accepted
    main_host_assert(arrayOf(P1, "now", "${3 * hour}"))

    // h0 -- h1 -- h21 -- l2
    //          -- h22 -- l3

    assert_(main_cli_assert(arrayOf(H1, "chain", "#", "heads", "blocked")).isEmpty())
    main_cli_assert(arrayOf(H1, "chain", "#", "heads")).let { str ->
        assert_(str.startsWith("3_"))
        str.split(' ').let {
            assert_(it.size == 2)
        }
    }

    // l4 dislikes h22
    val l4 = main_cli_assert(arrayOf(H0, "chain", "#", "dislike", h22, S0))

    // h0 -- h1 -- h21 -- l2 -- l4
    //         \-- h22 -- l3 --/

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1)
        }
        assert_(str.contains("4_"))
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    val h5x = main_cli_assert(arrayOf(H0, "chain", "#", "post", "inline", "h43"))

    // h0 -- h1 -- h21 -- l2 -- l4 -- h5x
    //         \-- h22 -- l3 --/

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it == h5x)
    }

////////

    main_host_assert(arrayOf(P1, "now", "${1 * hour}"))
    val lx = main_cli_assert(arrayOf(H1, "chain", "#", "dislike", h22, S0))     // one is not enough
    val ly = main_cli_assert(arrayOf(H1, "chain", "#", "dislike", h22, S0))     // one is not enough
    main_host_assert(arrayOf(P1, "now", "${4 * hour}"))
    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "#"))  // errors when merging

    // h0 -- h1 -- h21 -- l2 -- l4 -- h5x
    //         \-- h22 -- l3 --/  \-- lx -- ly

    // l4 dislikes h22 (reject it)
    // TODO: check if h22 contents are empty

    main_cli_assert(arrayOf(H1, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_cli_assert(arrayOf(H1, "chain", "#", "heads")).let {
        assert_(it.startsWith("5_"))
    }
}
@Test
fun m13_reps () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M13/")) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))

    main_host_assert(arrayOf(P0, "now", "0"))
    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "a1", S0))
    main_cli_assert(arrayOf(H0, "chain", "#", "post", "inline", "b2", S1)).let {
        main_cli(arrayOf(H0, S0, "chain", "#", "like", it))
    }

    // h0 -- a1      /-- l3
    //         \-- b2

    main_host_assert(arrayOf(P0, "now", "${3 * hour}"))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "1")
    }

    main_host_assert(arrayOf(P0, "now", "${25 * hour}"))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "2")
    }

    main_cli(arrayOf(H0, S1, "chain", "#", "post", "inline", "h3"))

    // h0 <-- h1 <-- l2
    //            \- h2 <-- h3

    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "1")
    }

    main_host_assert(arrayOf(P0, "now", "${50 * hour}"))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "3")
    }

    main_host_assert(arrayOf(P0, "now", "${53 * hour}"))
    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "h4", S1))

    // h0 <-- h1 <-- l2
    //            \- h2 <-- h3 <-- h4

    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "2")
    }

    main_host_assert(arrayOf(P0, "now", "${78 * hour}"))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "4") { it }
    }

    main_cli(arrayOf(H0, "chain", "#", "post", "inline", "h5", S1))

    // h0 <-- h1 <-- l2
    //            \- h2 <-- h3 <-- h4 <-- h5

    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "3")
    }

    main_host_assert(arrayOf(P0, "now", "${1000 * hour}"))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "5")
    }
}
@Test
fun m13_reps_pioneers () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M13_ps/")) }
    Thread.sleep(200)
    main_cli_assert(arrayOf(H0, "chains", "join", "#", PUB0, PUB1, PUB2))
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB0)).let {
        assert_(it == "10")
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB1)).let {
        assert_(it == "10")
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "reps", PUB2)).let {
        assert_(it == "10")
    }
}
@Test
fun m14_remove() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M140/")) }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#", PUB0))

    main_host_assert(arrayOf(P0, "now", "0"))

    val h1  = main_cli_assert(arrayOf(H0, S0, "chain", "#", "post", "inline", "h0"))
    val h21 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "h21"))
    val h20 = main_cli_assert(arrayOf(H0, S0, "chain", "#", "post", "inline", "h20"))

    // h0 -- h1 -- h21
    //         \-- h20

    main_cli_assert(arrayOf(H0, S0, "chain", "#", "post", "inline", "h30"))

    // h0 -- h1 -- h21
    //         \-- h20 -- h30

    main_host_assert(arrayOf(P0, "now", "${3 * hour}"))
    main_cli(arrayOf(H0, S0, "chain", "#", "post", "inline", "h40"))

    // h0 -- h1 -- h21
    //         \-- h20 -- h30 -- h40

    main_host_assert(arrayOf(P0, "now", "${6 * hour}"))
    val l21 = main_cli_assert(arrayOf(H0, S0, "chain", "#", "like", h21, "--why=l21"))

    // h0 -- h1 -- h21 -- l21
    //         \-- h20 -- h30 -- h40

    main_host_assert(arrayOf(P0, "now", "${9 * hour}"))

    val h51 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "h51"))

    // h0 -- h1 -- h21 -- l21 --------- h51
    //         \-- h20 -- h30 -- h40 --/

    val l60 = main_cli_assert(arrayOf(H0, S0, "chain", "#", "like", h51, "--why=l60"))

    // h0 -- h1 -- h21 -- l21 --------- h51 -- l60
    //         \-- h20 -- h30 -- h40 --/

    main_host_assert(arrayOf(P0, "now", "${34 * hour}"))
    val h7 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "h7"))

    // h0 -- h1 -- h21 -- l21 --------- h51 -- l60 -- h7
    //         \-- h20 -- h30 -- h40 --/

    // removes h21 (wont remove anything)
    val lx = main_cli_assert(arrayOf(H0, S0, "chain", "#", "dislike", h21, "--why=dislike"))

    // h0 -- h1 -- h21 -- l21 --------- h51 -- l60 -- h7 -- lx
    //         \-- h20 -- h30 -- h40 --/

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let {
        assert_(!it.contains("2_"))
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    main_host_assert(arrayOf(P0, "now", "${40 * hour}"))

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1) { it.size }
            it.forEach {
                assert_(it.startsWith("8_"))
            }
        }
    }
}
@Test
fun m15_rejected() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M150/")) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M151/", P1)) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))
    main_cli(arrayOf(H1, "chains", "join", "#", PUB0))

    main_host_assert(arrayOf(P0, "now", "0"))
    main_host_assert(arrayOf(P1, "now", "0"))

    main_cli(arrayOf(H0, S0, "chain", "#", "post", "inline", "0@h1"))
    val h2 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "1@h2"))
    main_cli(arrayOf(H0, S0, "chain", "#", "like", "--why=0@l2", h2))

    main_cli(arrayOf(H1, "peer", "localhost:$PORT0", "recv", "#"))

    // HOST-0
    // h0 <- 0@h1 <- 1@h2 <- 0@l2

    // HOST-1
    // h0 <- 0@h1 <- 1@h2 <- 0@l2

    // l3
    main_cli(arrayOf(H0, S0, "chain", "#", "dislike", h2, "--why=0@l3"))

    // HOST-0
    // h0 <- 0@h1 <- 1@h2 <- 0@l2 <- 0@l3-

    main_host_assert(arrayOf(P0, "now", "${5 * hour}"))
    main_host_assert(arrayOf(P1, "now", "${5 * hour}"))

    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1) { it.size }
            it.forEach { v -> assert_(v.startsWith("4_")) }
        }
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    main_cli_assert(arrayOf(H1, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1) { it.size }
            it.forEach { v -> assert_(v.startsWith("3_")) }
        }
    }
    main_cli_assert(arrayOf(H1, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_host_assert(arrayOf(P0, "now", "${25 * hour}"))
    main_host_assert(arrayOf(P1, "now", "${25 * hour}"))

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    main_cli(arrayOf(H1, S1, "chain", "#", "post", "inline", "1@h3"))

    // HOST-0
    // h0 <- 0@h1 <- 1@h2 <- 0@l2 <- 0@l3-

    // HOST-1
    // h0 <- 0@h1 <- 1@h2 <- 0@l2 <- 1@h3

    main_cli_assert(arrayOf(H1, "chain", "#", "heads")).let { str ->
        str.split(' ').let {
            assert_(it.size == 1) { it.size }
            it.forEach { v -> assert_(v.startsWith("4_")) }
        }
    }

    // send H1 -> H0
    // ~1@h3 will be rejected b/c 1@h2 is rejected in H0~
    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT0", "send", "#")).let {
        assert_(it.contains("1 / 1"))
    }

    // l4: try again after like // like will be ignored b/c >24h
    main_cli(arrayOf(H0, S0, "chain", "#", "like", h2))

    // HOST-0
    // h0 <- 0@h1 <- 0@l2 <-- 0@l3- <- 0@l4
    //            <- 1@h2 <-\ 1@h3     /
    //                  \-------------/

    // HOST-1
    // h0 <- 0@h1 <- 0@l2 |
    //            <- 1@h2 | <- 1@h3

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_cli_assert(arrayOf(H1, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
}
@Test
fun m16_likes_fronts () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M16/")) }
    Thread.sleep(200)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))

    main_host_assert(arrayOf(P0, "now", "0"))

    main_cli(arrayOf(H0, S0, "chain", "#", "post", "inline", "0@h1"))
    val h2 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "1@h2"))
    main_cli(arrayOf(H0, S0, "chain", "#", "like", h2, "--why=0@l2"))

    // HOST-0
    // h0 <- 0@h1 <-- 0@l2
    //            <- 1@h2

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    main_host_assert(arrayOf(P0, "now", "${3 * hour}"))

    // l4 dislikes h2: h2 should remain accepted b/c h2<-l3
    main_cli(arrayOf(H0, S0, "chain", "#", "post", "inline", "0@h3"))
    main_cli(arrayOf(H0, S0, "chain", "#", "dislike", h2, "--why=0@l3"))

    // HOST-0
    // h0 <- 0@h1 <-- 0@l2 \ 0@h3 -- 0@l3
    //            <- 1@h2  /

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let {
        assert_(it.startsWith("5_"))
    }
}
@Test
fun m17_likes_day () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M17/")) }
    Thread.sleep(300)
    main_cli(arrayOf(H0, "chains", "join", "#", PUB0))

    main_host_assert(arrayOf(P0, "now", "0"))

    main_cli(arrayOf(H0, S0, "chain", "#", "post", "inline", "0@h1"))
    val h2 = main_cli_assert(arrayOf(H0, S1, "chain", "#", "post", "inline", "1@h2"))
    main_cli(arrayOf(H0, S0, "chain", "#", "like", h2))

    // HOST-0
    // h0 <- 0@h1 <-- 0@l2
    //            <- 1@h2

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }

    main_host_assert(arrayOf(P0, "now", "${25 * hour}"))

    // l4 dislikes h2: h2 should remain accepted b/c (l3-h2 > 24h)
    main_cli(arrayOf(H0, S0, "chain", "#", "dislike", h2))

    // HOST-0
    // h0 <- 0@h1 <-- 0@l2 <-- 0@h3 <- 0@l4
    //            <- 1@h2 <-/

    main_cli_assert(arrayOf(H0, "chain", "#", "heads", "blocked")).let {
        assert_(it.isEmpty())
    }
    main_cli_assert(arrayOf(H0, "chain", "#", "heads")).let {
        assert_(it.startsWith("4_"))
    }
}
@Test
fun m19_remove() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M14/")) }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#", PUB0))

    main_host_assert(arrayOf("now", "0"))

    val b1 = main_cli_assert(arrayOf(S1, "chain", "#", "post", "inline", "b1"))
    val l2 = main_cli_assert(arrayOf(S0, "chain", "#", "like", b1))

    // gen -- b1 -- l2

    main_host_assert(arrayOf("now", "${1*day+100}"))
    main_cli_assert(arrayOf("chain", "#", "reps", PUB1)).let {
        assert_(it == "2")
    }
    main_cli_assert(arrayOf("chain", "#", "get", "payload", b1)).let {
        assert_(it == "b1")
    }

    val l3 = main_cli_assert(arrayOf(S1, "chain", "#", "dislike", b1))

    // gen -- b1 -- l2 -- l3

    main_cli_assert(arrayOf("chain", "#", "reps", PUB1)).let {
        assert_(it == "0")
    }
    main_cli_assert(arrayOf("chain", "#", "get", "payload", b1)).let {
        assert_(it == "")
    }
}
@Test
fun m20_posts_20 () {
    val PUB = "300C0F41FA37EDD0A812F88956EB005C68967ED4F9ADA8CDE7E64C030D4A2F39"
    val PVT = "8A0E17D9B3C29152A797D061C619CFBA829BC7325ED72831CC59C0A7148CA9F8300C0F41FA37EDD0A812F88956EB005C68967ED4F9ADA8CDE7E64C030D4A2F39"
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M20/")) }
    Thread.sleep(500)
    main_cli(arrayOf("chains", "join", "#crdt", PUB0))

    val n = 23
    for (i in 1..n) {
        main_cli_assert(arrayOf(H0, S0, "chain", "#crdt", "post", "inline", "Post $n"))
    }

    val ret = main_cli_assert(arrayOf(H0, "chain", "#crdt", "heads"))
    assert_(ret.startsWith("23_"))
}

@Test
fun n01_merge_tie () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N01.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N01.2/", P2)) }
    Thread.sleep(200)

    main_host_assert(arrayOf(P1, "path")).let {
        assert(it == "//tmp/freechains/tests/N01.1//")
    }

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val a1 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "a1"))
    val la = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", a1, "--why=la"))
    val b1 = main_cli_assert(arrayOf(H1, S2, "chain", "#", "post", "inline", "b1"))
    val lb = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", b1, "--why=lb"))

    // gen -- a1 -- la -- b1 -- lb

    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    assert(s1 == "4 / 4" && r1 == "0 / 0")

    assert("1" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
    assert("1" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))
    assert("1" == main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB1)))
    assert("1" == main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB2)))

    val a2 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "a2"))
    val b2 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "b2"))

    //                            /-- a2    // H1
    // gen -- a1 -- la -- b1 -- lb
    //                            \-- b2    // H2

    val s2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val r2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    assert(s2 == "1 / 1" && r2 == "1 / 1")

    assert("0" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
    assert("0" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))
    assert("0" == main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB1)))
    assert("0" == main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB2)))

    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    assert(v1 == v2)
    assert(v1.endsWith(if (a2 > b2) a2 else b2))
}
@Test
fun n02_merge_win () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N02.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N02.2/", P2)) }
    Thread.sleep(200)

    let {
        main_host_assert(arrayOf(P1, "now", "0"))
        main_host_assert(arrayOf(P2, "now", "0"))
        main_host_assert(arrayOf(P1, "now")).let {
            assert(it.toInt() < 50)
        }
    }

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    let {
        val a1 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "a1"))
        val b1 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "b1"))

        val la = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", a1, "--why=la"))
        val lb = main_cli_assert(arrayOf(H2, S0, "chain", "#", "like", b1, "--why=lb"))

        // gen -- a1 -- la
        //    \-- b1 -- lb

        main_host_assert(arrayOf(P1, "now", "${1*day + 1*hour}"))
        main_host_assert(arrayOf(P2, "now", "${1*day + 1*hour}"))
        val b3 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "b3"))

        // gen -- a1 -- la
        //    \-- b1 -- lb -- b3

        val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
        val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
        assert(s1 == "2 / 2" && r1 == "3 / 3")

        val x1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
        val x2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
        //println("-=-=-=-")
        //println(x1)
        //println(x2)
        //println(b1)
        //println(b3)

        assert("2" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
        //println(main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))
        assert("1" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))
    }

    main_host_assert(arrayOf(P1, "now", "${1*day + 15*hour}"))
    main_host_assert(arrayOf(P2, "now", "${1*day + 15*hour}"))
    assert("2" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
    assert("2" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))

    main_host_assert(arrayOf(P1, "now", "${2*day + 2*hour}"))
    main_host_assert(arrayOf(P2, "now", "${2*day + 2*hour}"))
    assert("2" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
    assert("3" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))

    val x4 = main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "common"))
    main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#")).let {
        assert(it == "1 / 1")
    }

    // gen -- a1 -- la ------- x4
    //    \-- b1 -- lb -- b3--/

    assert("2" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB1)))
    assert("3" == main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2)))

    // gen -- a1 -- la ------- x4 -- a5
    //    \-- b1 -- lb -- b3--/  \-- b5

    let {
        val a5 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "a5"))
        val b5 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "b5"))

        val s2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
        val r2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
        assert(s2 == "1 / 1" && r2 == "1 / 1")

        val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
        val v2 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
        assert(v1 == v2)
        assert(v1.endsWith(a5))
    }
}
@Test
fun n03_merge_ok () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N03.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N03.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val As = arrayOf (
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a1")),
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a2")),
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a3")),
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a4")),
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a5")),
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a6"))
    )

    val Bs = arrayOf (
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b1")),
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b2")),
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b3")),
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b4")),
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b5")),
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b6"))
    )

    // gen -- a1 ... a6
    //    \-- b1 ... b6

    //println("-=-=-=-=-")
    main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    // 0_4B54E 1_3591F3 2_FCC6 3_99F09EEE7 4_C95F5 5_BDDA7DB9 6_6AB7985D71E46165F22A84028
    // 0 1 2 3 4 5 6
    // a
    // 0 1 2 3 a b c 4 d 5 e 6 f

    //println("-=-=-=-=-")
    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    //println(main_cli_assert(arrayOf(H2, "chain", "#", "consensus")))
    //println("-=-=-=-=-")
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    assert(s1 == "6 / 6" && r1 == "6 / 6")
    //TODO()

    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(v1)
    //println(v2)
    assert(v1 == v2)
}
@Test
fun n04_merge_fail () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N04.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N04.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val As = (1..101).map {
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a$it"))
    }
    val Bs = (1..101).map {
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b$it"))
    }

    // gen -- a1 ... a100     // H1
    //    \-- b1 ... b100     // H2

    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    assert(s1 == "101 / 101" && r1 == "101 / 101")

    //println("-=-=-=-")
    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(v1)
    //println(v2)
    assert(v1 != v2)
    assert(v1.contains(As[0]))
    assert(v2.contains(Bs[0]))
}
@Test
fun n05_merge_fail () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N04.X/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N04.Y/", P2)) }
    Thread.sleep(200)

    main_host_assert(arrayOf(P1, "now", 0.toString()))

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val a1 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a1"))
    val b1 = main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b1"))

    main_host_assert(arrayOf(P1, "now", (8*day).toString()))

    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    assert(s1 == "1 / 1" && r1 == "1 / 1")

    //println("-=-=-=-")
    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(v1)
    //println(v2)
    assert(v1 != v2)
    assert(v1.contains(b1))
    assert(v2.contains(a1))
}
@Test
fun n05_merge_ok () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N05.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N05.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0, PUB1, PUB2))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0, PUB1, PUB2))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val a1 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a1"))
    val b2 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "b2"))
    val c1 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "c1"))

    // gen -- a1 -- b2
    //    \-- c1

    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    //println(s1) ; println(r1)
    assert(s1 == "2 / 2" && r1 == "1 / 1")

    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    assert(v1 == v2)
    assert(v1.endsWith(b2))
    assert(v2.endsWith(b2))
}
@Test
fun n06_merge_ok () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N06.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N06.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val now = getNow()
    for (i in 1..12) {
        val n = i%6 + 1
        for (j in 1..n) {
            main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a_${i}_$j"))
            main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b_${i}_$j"))
        }
        val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
        val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
        assert(s1 == "$n / $n" && r1 == "$n / $n")
        //println("-=-=-=-")
        val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
        val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
        //println("DAY=$i, n=$n, nxt=${4*i}")
        //println(v1)
        //println(v2)
        //println(i)
        assert(v1 == v2)
        main_host_assert(arrayOf(P1, "now", (now + 4*i*day).toString()))
        main_host_assert(arrayOf(P2, "now", (now + 4*i*day).toString()))
    }

    for (j in 1..5) {
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a_X_$j"))
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b_X_$j"))
    }
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    assert(s1 == "5 / 5" && r1 == "5 / 5")

    for (j in 6..10) {
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a_X_$j"))
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b_X_$j"))
    }
    val r2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    val s2 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    assert(s2 == "5 / 5" && r2 == "5 / 5")

    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    assert(v1 == v2)
}
@Test
fun n07_merge_fail () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N07.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N07.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))
    val gen = main_cli_assert(arrayOf(H2, "chain", "#", "genesis"))

    val now = getNow()
    for (i in 1..12) {
        val n = i%6 + 1
        for (j in 1..n) {
            main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a_${i}_$j"))
            main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b_${i}_$j"))
        }
        val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
        val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
        assert(s1 == "$n / $n" && r1 == "$n / $n")
        val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
        val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
        //println("DAY=$i, n=$n, nxt=${4*i}")
        assert(v1 == v2)
        main_host_assert(arrayOf(P1, "now", (now + 4*i*day).toString()))
        main_host_assert(arrayOf(P2, "now", (now + 4*i*day).toString()))
    }

    for (j in 1..11) {
        main_cli_assert(arrayOf(H1, S0, "chain", "#", "post", "inline", "a_X_$j"))
        main_cli_assert(arrayOf(H2, S0, "chain", "#", "post", "inline", "b_X_$j"))
    }
    val r1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "recv", "#"))
    val s1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    assert(s1 == "11 / 11" && r1 == "11 / 11")
    val v1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val v2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(v1)
    //println(v2)
    assert(v1 == v2)
    /*
    let {
        val a1 = v1.split(" ")
        val a2 = v2.split(" ")
        assert(a1.size == a2.size)
        assert(a1[a1.size-12*2] == a2[a2.size-12*2])
        assert(a1[a1.size-11*2] != a2[a2.size-11*2])
    }
     */
}
@Test
fun n08_merge_fail () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N08.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N08.2/", P2)) }
    Thread.sleep(200)

    main_host_assert(arrayOf(P1, "now", "0"))
    main_host_assert(arrayOf(P2, "now", "0"))

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0))
    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0))

    //                           /- a5 -- a6 (dislike b3)
    // G -- a1 -- x2 -- b3 -- x4
    //                           \- b5 -- b6 (dislike a1)

    val a1 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "a1"))
    val x2 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", a1))
    val b3 = main_cli_assert(arrayOf(H1, S2, "chain", "#", "post", "inline", "b3"))
    val x4 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", b3))

    val s = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    assert(s == "4 / 4")

    main_host_assert(arrayOf(P1, "now", "${25 * hour}"))
    main_host_assert(arrayOf(P2, "now", "${25 * hour}"))

    val a5 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "dislike", b3))
    val a6 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "dislike", b3))
    val b5 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "dislike", a1))
    val b6 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "dislike", a1))

    val r1 = main_cli_assert(arrayOf(H1, "chain", "#", "reps", PUB2))
    val r2 = main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB1))
    //println(r1)
    //println(r2)

    val c1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val c2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(c1)
    //println(c2)

    val t1 = main_cli_assert(arrayOf(H1, "peer", "localhost:$PORT2", "send", "#"))
    val t2 = main_cli_assert(arrayOf(H2, "peer", "localhost:$PORT1", "send", "#"))
    //println(t1)
    //println(t2)

    val d1 = main_cli_assert(arrayOf(H1, "chain", "#", "consensus"))
    val d2 = main_cli_assert(arrayOf(H2, "chain", "#", "consensus"))
    //println(d1)
    //println(d2)
}
@Test
fun n09_merge_fail_12h () {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N09.1/", P1)) }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N09.2/", P2)) }
    Thread.sleep(200)

    main_cli_assert(arrayOf(H1, "chains", "join", "#", PUB0, PUB1, PUB2))
    val h1 = main_cli_assert(arrayOf(H1, S3, "chain", "#", "post", "inline", "from 3 1"))
    val h2 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", h1))
    val h3 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "like", h2))
    //main_host_assert(arrayOf(P0, "now", "${1 * day + 1 * min}"))
    val h4 = main_cli_assert(arrayOf(H1, S3, "chain", "#", "post", "inline", "from 3 2"))
    val h5 = main_cli_assert(arrayOf(H1, S1, "chain", "#", "post", "inline", "from 1"))
    val c1 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "consensus"))
    println(c1.split(" ").map { it.take(5) }.joinToString(" "))
    assert(c1.contains(h4))
    assert(c1.contains(h5))

    // S3 is a newbie. His 2nd post uses depends on 12h->0h due to S0-S1 in sequence.
    // gen - S3 - S0 - S1 - S3
    //     - S2 - S0* - S1*
    // The other branch transfers S0-S1 reps to S2. When it merges, 12h->0h is no longer true.

    main_cli_assert(arrayOf(H2, "chains", "join", "#", PUB0, PUB1, PUB2))
    val n1 = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "from 2: 1"))
    for (i in 1..8) {
        val n2 = main_cli_assert(arrayOf(H2, S0, "chain", "#", "like", n1))
        val n3 = main_cli_assert(arrayOf(H2, S1, "chain", "#", "like", n1))
    }
    val nn = main_cli_assert(arrayOf(H2, S2, "chain", "#", "post", "inline", "from 2: 2"))
    main_cli_assert(arrayOf(H2, "peer", "localhost:$PORT1", "send", "#"))
    val c2 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "consensus"))

    println(h1)
    println(c2.split(" ").map { it.take(5) }.joinToString(" "))
    println(main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB0)))
    println(main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB1)))
    println(main_cli_assert(arrayOf(H2, "chain", "#", "reps", PUB2)))
    assert(!c2.contains(h4))
    assert(!c2.contains(h5))

    // gen - S3 - S0 - S1 - S3
    //     - S2 - S0* - S1*

    val x5 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "like", h4))
    val c3 = main_cli_assert(arrayOf(H1, S0, "chain", "#", "consensus"))
    println(c1.split(" ").map { it.take(5) }.joinToString(" "))
    println(c2.split(" ").map { it.take(5) }.joinToString(" "))
    println(c3.split(" ").map { it.take(5) }.joinToString(" "))
    assert(c3.contains(h4))
    assert(c3.contains(h5))
}

@Test
fun x01_sends () {
    val PVT = "6F99999751DE615705B9B1A987D8422D75D16F5D55AF43520765FA8C5329F7053CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322"
    val PUB = "3CCAF4839B1FDDF406552AF175613D7A247C5703683AEC6DBDF0BB3932DD8322"
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M19-0/"))     }
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/M19-1/", P1)) }
    Thread.sleep(500)
    main_cli_assert(arrayOf(H0, "chains", "join", "@!$PUB"))
    main_cli_assert(arrayOf(H1, "chains", "join", "@!$PUB"))

    val n = 100
    for (i in 1..n) {
        main_cli_assert(arrayOf(H0, "--sign=$PVT", "chain", "@!$PUB", "post", "inline", "$i"))
    }

    val ret = main_cli_assert(arrayOf(H0, "peer", "localhost:$PORT1", "send", "@!$PUB"))
    assert_(ret == "$n / $n")
}

@Disabled
@Test
fun x02_cons() {
    thread {
        thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N08.1/", P1)) }
        thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/N08.2/", P2)) }
    }
    Thread.sleep(200)
    main_cli(arrayOf("chains", "join", "#xxx", PUB0))
    for (i in 0..1000) {
        //val old = getNow()
        main_cli(arrayOf("chain", "#xxx", "post", "inline", i.toString(), S0))
        //println(getNow()-old)
    }
}
@Disabled   // requires deterministic getNow
@Test
fun x03_cons() {
    val N = 9
    val rand = Random(2)

    for (i in 1..N) {
        thread {
            main_host_assert(arrayOf("start", "/tmp/freechains/tests/X03.$i/", "--port=${8330+i}"))
        }
    }
    Thread.sleep(500)
    for (i in 1..N) {
        main_host_assert(arrayOf("--port=${8330+i}", "now", "0"))
        main_cli_assert(arrayOf("chains", "join", "@$PUB0", "--port=${8330+i}"))
    }
    for (i in 1..5000) {
        println(">>>>> $i")
        for (j in 1..N) {
            main_host_assert(arrayOf("--port=${8330+j}", "now", (i*hour).toString()))
        }

        val p1 = 8330 + rand.nextInt(2)+1
        println(">>> POST $p1/$i")
        main_cli(arrayOf("chain", "@$PUB0", "post", "inline", "$p1/$i", S0, "--port=$p1"))
        if (i % 2 == 1) {
            for (j in 1..3) {
                val p2 = 8330 + rand.nextInt(N)+1
                if (p1 != p2) {
                    println(">>> SEND $p1 -> $p2")
                    main_cli(arrayOf("--port=$p1", "peer", "localhost:$p2", "send", "@$PUB0"))
                }
            }
        }
    }
    for (i in 1..N) {
        for (j in 1..N) {
            if (i != j) {
                println(">>> SYNC $i -> $j")
                main_cli_assert(arrayOf("--port=${8330+i}", "peer", "localhost:${8330+j}", "send", "@$PUB0"))
            }
        }
    }
    val c1 = main_cli_assert(arrayOf("chain", "@$PUB0", "consensus", "--port=${8330+1}"))
    //println(c1.split(" ").joinToString("\n"))
    for (i in 2..N) {
        val c2 = main_cli_assert(arrayOf("chain", "@$PUB0", "consensus", "--port=${8330+i}"))
        assert(c1 == c2) {
            ("[1]: "+(c1.split(" ").map { it.take(5) })+"\n[$i]: "+(c2.split(" ").map { it.take(5) }))
        }
    }
    println("!!! DONE !!!")
}
@Disabled
@Test
fun x04_cons() {
    thread { main_host_assert(arrayOf("start", "/tmp/freechains/tests/X03.1/", "--port=${8330 + 2}")) }
    Thread.sleep(200)
    val c1 = main_cli_assert(arrayOf("chain", "@$PUB0", "consensus", "--port=${8330+2}"))
    println(c1.split(" ").joinToString("\n"))
}
