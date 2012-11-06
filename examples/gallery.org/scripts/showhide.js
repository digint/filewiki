function show(id) {
    document.getElementById(id).style.display = 'block';
}
function hide(id) {
    document.getElementById(id).style.display = 'none';
}
function toggle(id) {
    var ele=document.getElementById(id);
    if(ele.style.display != 'block')
	ele.style.display = 'block';
    else
	ele.style.display = 'none';
}
