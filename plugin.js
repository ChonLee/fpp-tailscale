function runAction(action){
    const logDiv = document.getElementById('log');
    const authDiv = document.getElementById('authLink');

    fetch(`?action=${action}`)
    .then(response => response.text())
    .then(data => {
        if(action === 'install') {
            logDiv.innerText = data;
        }
        if(action === 'up' || action === 'down') {
            updateStatus();
        }
    });

    if(action === 'install') {
        fetch('?action=auth')
        .then(res => res.text())
        .then(link => {
            if(link){
                authDiv.innerHTML = `<a href="${link}" target="_blank">Authorize Tailscale</a>`;
            }
        });
    }
}

function updateStatus(){
    fetch('?action=status')
    .then(res => res.json())
    .then(data => {
        const statusDiv = document.getElementById('status');
        if(data && Object.keys(data).length){
            statusDiv.innerText = JSON.stringify(data, null, 2);
            document.getElementById('authLink').style.display = 'none';
        } else {
            statusDiv.innerText = "Tailscale not connected";
            document.getElementById('authLink').style.display = 'block';
            fetch('?action=auth')
            .then(res => res.text())
            .then(link => {
                if(link) document.getElementById('authLink').innerHTML = `<a href="${link}" target="_blank">Authorize Tailscale</a>`;
            });
        }
    });
}
