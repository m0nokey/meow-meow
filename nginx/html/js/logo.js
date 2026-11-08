(() => {
    const output = document.getElementById('logo');
    const animationDelays = [0.0001, 0.0003, 0.0006, 0.0009, 0.0011, 0.0013];
    const animationDelayStartFrames = [0, 12, 15, 18, 20, 22];
    const monkey = [
        '.-"-.',
        '_/.-.-.\\_',
        '( ( o o ) )',
        '|/  "  \\|',
        '\\.__. /',
        '/`"""`\\',
        '/   >_  \\'
    ];

    const randomBit = () => (Math.random() < 0.5 ? '0' : '1');

    const renderMatrix = (matrix) => {
        output.textContent = matrix.map((row) => `  ${row.join(' ')}`).join('\n');
    };

    const renderRows = (rows) => {
        output.textContent = rows.join('\n');
    };

    const makeMatrix = () => Array.from(
        { length: 9 },
        () => Array.from({ length: 9 }, () => ' ')
    );

    const makeBinaryMonkeyRows = (monkeyRows) => [
        '  ? ? ? ? ? ? ? ? ?',
        `  ? ? ? ${monkeyRows[0]} ? ? ?`,
        `  ? ? ${monkeyRows[1]} ? ?`,
        `  ? ?${monkeyRows[2]}? ?`,
        `  ? ? ${monkeyRows[3]} ? ?`,
        `  ? ? ?${monkeyRows[4]}? ? ?`,
        `  ? ? ?${monkeyRows[5]}? ? ?`,
        `  ? ? ${monkeyRows[6]} ? ?`,
        '  ? ? ? ? ? ? ? ? ?'
    ];

    const makeFrameRows = () => [
        '  ? ? ? ? ? ? ? ? ?',
        '  ?     .-"-.     ?',
        '  ?   _/.-.-.\\_   ?',
        '  ?  ( ( o o ) )  ?',
        '  ?   |/  "  \\|   ?',
        '  ?    \\.__. /    ?',
        '  ?    /`"""`\\    ?',
        '  ?   /   >_  \\   ?',
        '  ? ? ? ? ? ? ? ? ?'
    ];

    const makeLogoRows = () => makeBinaryMonkeyRows(monkey);

    const revealRow = (row) => {
        let revealed = row;

        while (revealed.includes('?')) {
            revealed = revealed.replace('?', randomBit());
        }

        return revealed;
    };

    const animateFinalRows = (rows) => {
        let row = 0;
        let nextRowAt = 0;
        const startedAt = window.performance.now();

        const draw = (now) => {
            const elapsed = now - startedAt;

            while (row < rows.length && elapsed >= nextRowAt) {
                rows[row] = revealRow(rows[row]);
                renderRows(rows);
                row += 1;
                nextRowAt += 1.8;
            }

            if (row < rows.length) {
                window.requestAnimationFrame(draw);
            }
        };

        draw(window.performance.now());
    };

    const animate = () => {
        const matrix = makeMatrix();
        let frame = 0;
        let row = 0;
        let column = 0;
        let delayIndex = 0;
        let nextOperationAt = 0;
        const startedAt = window.performance.now();

        const draw = (now) => {
            const elapsed = now - startedAt;
            let changed = false;

            while (frame < 25 && elapsed >= nextOperationAt) {
                for (let index = 0; index < animationDelayStartFrames.length - 1; index += 1) {
                    if (frame >= animationDelayStartFrames[index + 1]) {
                        delayIndex = index;
                    }
                }

                matrix[row][column] = randomBit();
                changed = true;
                nextOperationAt += animationDelays[delayIndex] * 1000;
                column += 1;

                if (column === 9) {
                    column = 0;
                    row += 1;
                    nextOperationAt += 0.1;

                    if (row === 9) {
                        row = 0;
                        frame += 1;
                    }
                }
            }

            if (changed) {
                renderMatrix(matrix);
            }

            if (frame < 25) {
                window.requestAnimationFrame(draw);
                return;
            }

            const rows = Math.random() < 0.5 ? makeFrameRows() : makeLogoRows();
            animateFinalRows(rows);
        };

        draw(window.performance.now());
    };

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', animate, { once: true });
    } else {
        animate();
    }
})();
